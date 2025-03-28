"""Base and specialized sync services for Gmail and Calendar synchronization"""

# pylint: disable=E1101, W0718, W0719
from abc import ABC, abstractmethod
from datetime import datetime, timezone, timedelta
import asyncio
import uuid
from typing import Dict
from app.config.arangodb_constants import CollectionNames

from app.utils.logger import logger
from app.connectors.google.core.arango_service import ArangoService
from app.connectors.google.gmail.core.gmail_admin_service import GmailAdminService
from app.connectors.google.gmail.core.gmail_user_service import GmailUserService
from app.connectors.google.gmail.handlers.change_handler import GmailChangeHandler
from app.connectors.core.kafka_service import KafkaService
from app.config.configuration_service import ConfigurationService


class GmailSyncProgress:
    """Class to track sync progress"""

    def __init__(self):
        self.total_files = 0
        self.processed_files = 0
        self.percentage = 0
        self.status = "initializing"
        self.last_updated = datetime.now(
            timezone(timedelta(hours=5, minutes=30))).isoformat()


class BaseGmailSyncService(ABC):
    """Abstract base class for sync services"""

    def __init__(
        self,
        config: ConfigurationService,
        arango_service: ArangoService,
        kafka_service: KafkaService,
        celery_app
    ):
        self.config = config
        self.arango_service = arango_service
        self.kafka_service = kafka_service
        self.celery_app = celery_app

        # Common state
        self.drive_workers = {}
        self.progress = GmailSyncProgress()
        self._current_batch = None
        self._pause_event = asyncio.Event()
        self._pause_event.set()
        self._stop_requested = False

        # Locks
        self._sync_lock = asyncio.Lock()
        self._transition_lock = asyncio.Lock()
        self._worker_lock = asyncio.Lock()
        self._progress_lock = asyncio.Lock()

        # Configuration
        self._hierarchy_version = 0
        self._sync_task = None
        self.batch_size = 100

    @abstractmethod
    async def connect_services(self) -> bool:
        """Connect to required services"""
        pass

    @abstractmethod
    async def initialize(self) -> bool:
        """Initialize sync service"""
        pass

    @abstractmethod
    async def perform_initial_sync(self, org_id, action: str = "start", resume_hierarchy: Dict = None) -> bool:
        """Perform initial sync"""
        pass

    async def start(self, org_id) -> bool:
        logger.info("🚀 Starting Gmail sync, Action: start")
        async with self._transition_lock:
            try:
                # Get current user
                user = await self.gmail_user_service.list_individual_user()
                user = user[0]
                
                # Check current state using get_user_sync_state
                sync_state = await self.arango_service.get_user_sync_state(user['email'], 'gmail')
                current_state = sync_state.get('syncState') if sync_state else 'NOT_STARTED'

                if current_state == 'RUNNING':
                    logger.warning("💥 Gmail sync service is already running")
                    return False

                if current_state == 'PAUSED':
                    logger.warning("💥 Gmail sync is paused, use resume to continue")
                    return False

                # Cancel any existing task
                if self._sync_task and not self._sync_task.done():
                    self._sync_task.cancel()
                    try:
                        await self._sync_task
                    except asyncio.CancelledError:
                        pass

                # Update state in Arango
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'RUNNING',
                    'gmail'
                )

                # Start fresh sync
                self._sync_task = asyncio.create_task(
                    self.perform_initial_sync(org_id, action="start")
                )

                logger.info("✅ Gmail sync service started")
                return True

            except Exception as e:
                logger.error(f"❌ Failed to start Gmail sync service: {str(e)}")
                return False

    async def pause(self, org_id) -> bool:
        logger.info("⏸️ Pausing Gmail sync service")
        async with self._transition_lock:
            try:
                # Get current user
                user = await self.gmail_user_service.list_individual_user()
                user = user[0]
                
                # Check current state using get_user_sync_state
                sync_state = await self.arango_service.get_user_sync_state(user['email'], 'gmail')
                current_state = sync_state.get('syncState') if sync_state else 'NOT_STARTED'

                if current_state != 'RUNNING':
                    logger.warning("💥 Gmail sync service is not running")
                    return False

                self._stop_requested = True

                # Update state in Arango
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'PAUSED',
                    'gmail'
                )

                # Cancel current sync task
                if self._sync_task and not self._sync_task.done():
                    self._sync_task.cancel()
                    try:
                        await self._sync_task
                    except asyncio.CancelledError:
                        pass

                logger.info("✅ Gmail sync service paused")
                return True

            except Exception as e:
                logger.error(f"❌ Failed to pause Gmail sync service: {str(e)}")
                return False

    async def resume(self, org_id) -> bool:
        logger.info("🔄 Resuming Gmail sync service")
        async with self._transition_lock:
            try:
                # Get current user
                user = await self.gmail_user_service.list_individual_user()
                user = user[0]
                
                # Check current state using get_user_sync_state
                sync_state = await self.arango_service.get_user_sync_state(user['email'], 'gmail')
                if not sync_state:
                    logger.warning("⚠️ No user found, starting fresh")
                    return await self.start(org_id)

                current_state = sync_state.get('syncState')
                if current_state == 'RUNNING':
                    logger.warning("💥 Gmail sync service is already running")
                    return False

                if current_state != 'PAUSED':
                    logger.warning("💥 Gmail sync was not paused, use start instead")
                    return False

                # Update state in Arango
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'RUNNING',
                    'gmail'
                )

                self._pause_event.set()
                self._stop_requested = False

                # Start sync with resume state
                self._sync_task = asyncio.create_task(
                    self.perform_initial_sync(org_id, action="resume")
                )

                logger.info("✅ Gmail sync service resumed")
                return True

            except Exception as e:
                logger.error(f"❌ Failed to resume Gmail sync service: {str(e)}")
                return False

    async def _should_stop(self) -> bool:
        """Check if operation should stop"""
        if self._stop_requested:
            # Get current user
            user = await self.gmail_user_service.list_individual_user()
            user = user[0]
            
            await self.arango_service.update_user_sync_state(
                user['email'],
                'PAUSED',
                'gmail'
            )
            logger.info("✅ Gmail sync state updated before stopping")
            return True
        return False

    async def stop(self) -> bool:
        """Stop the sync service"""
        async with self._transition_lock:
            try:
                logger.info("🚀 Stopping Gmail sync service")
                self._stop_requested = True

                # Wait for current operations to complete
                if self._sync_lock.locked():
                    async with self._sync_lock:
                        pass

                # Get current user and update state
                user = await self.gmail_user_service.list_individual_user()
                user = user[0]
                
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'STOPPED',
                    'gmail'
                )

                await self.gmail_user_service.disconnect()
                await self.arango_service.disconnect()

                # Reset states
                self._stop_requested = False  # Reset for next run

                logger.info("✅ Gmail sync service stopped")
                return True

            except Exception as e:
                logger.error("❌ Failed to stop Gmail sync service: %s", str(e))
                return False

    async def process_sync_period_changes(self, start_token: str, user_service) -> bool:
        """Delegate change processing to ChangeHandler"""
        logger.info("🚀 Delegating change processing to ChangeHandler")
        return await self.change_handler.process_sync_period_changes(start_token, user_service)


    async def process_batch(self, metadata_list):
        """Process a single batch with atomic operations"""
        logger.info("🚀 Starting batch processing with %d items",
                    len(metadata_list))
        batch_start_time = datetime.now(timezone.utc)

        try:
            if await self._should_stop():
                logger.info("⏹️ Stop requested, halting batch processing")
                return False

            async with self._sync_lock:
                logger.debug("🔒 Acquired sync lock for batch processing")
                # Prepare nodes and edges for batch processing
                messages = []
                attachments = []
                records = []
                permissions = []
                recordRelations = []
                existing_messages = []
                existing_attachments = []

                logger.debug(
                    "📊 Processing metadata list of size: %d", len(metadata_list))
                for metadata in metadata_list:
                    # logger.debug(
                    #     "📝 Starting metadata processing: %s", metadata)
                    thread_metadata = metadata['thread']
                    messages_metadata = metadata['messages']
                    attachments_metadata = metadata['attachments']
                    permissions_metadata = metadata['permissions']

                    logger.debug("📨 Messages in current metadata: %d",
                                 len(messages_metadata))
                    logger.debug("📎 Attachments in current metadata: %d", len(
                        attachments_metadata))

                    if not thread_metadata:
                        logger.warning(
                            "❌ No metadata found for thread, skipping")
                        continue

                    thread_id = thread_metadata['id']
                    logger.debug("🧵 Processing thread ID: %s", thread_id)
                    if not thread_id:
                        logger.warning(
                            "❌ No thread ID found for thread, skipping")
                        continue

                    # Process messages
                    logger.debug("📨 Processing %d messages for thread %s", len(
                        messages_metadata), thread_id)

                    # Sort messages by internalDate to identify the first message in thread
                    sorted_messages = sorted(messages_metadata, key=lambda x: int(
                        x['message'].get('internalDate', 0)))

                    previous_message_key = None  # Track previous message to create chain

                    for i, message_data in enumerate(sorted_messages):
                        message = message_data['message']
                        message_id = message['id']
                        logger.debug("📝 Processing message: %s", message_id)
                        headers = message.get('headers', {})

                        subject = headers.get('Subject', 'No Subject')
                        date = headers.get('Date', None)
                        from_email = headers.get('From', None)
                        to_email = headers.get('To', '').split(', ')
                        cc_email = headers.get('Cc', '').split(', ')
                        bcc_email = headers.get('Bcc', '').split(', ')
                        message_id_header = headers.get('Message-ID', None)

                        # Check if message exists
                        logger.debug(
                            "🔍 Checking if message %s exists in ArangoDB", message_id)
                        existing_message = self.arango_service.db.aql.execute(
                            'FOR doc IN mails FILTER doc.externalMessageId == @message_id RETURN doc',
                            bind_vars={'message_id': message_id}
                        )
                        existing_message = next(existing_message, None)

                        if existing_message:
                            logger.debug(
                                "♻️ Message %s already exists in ArangoDB", message_id)
                            existing_messages.append(message_id)
                            # Keep track of previous message key for chain
                            previous_message_key = existing_message['_key']
                        else:
                            logger.debug(
                                "➕ Creating new message record for %s", message_id)
                            message_record = {
                                '_key': str(uuid.uuid4()),
                                'externalMessageId': message_id,
                                'threadId': thread_id,
                                'isParent': i == 0,  # First message in sorted list is parent
                                'internalDate': message.get('internalDate'),
                                'subject': subject,
                                'date': date,
                                'from': from_email,
                                'to': to_email,
                                'cc': cc_email,
                                'bcc': bcc_email,
                                'messageIdHeader': message_id_header,
                                # Move thread history to message
                                'historyId': thread_metadata.get('historyId'),
                                'webUrl': f"https://mail.google.com/mail?authuser={{user.email}}#all/{message_id}",
                                'labelIds': message.get('labelIds', []),
                                'lastSyncTime': int(datetime.now(timezone.utc).timestamp())
                            }

                            record = {
                                "_key": message_record['_key'],
                                "recordName": "placeholder",
                                "recordType": "MESSAGE",
                                "version": 0,
                                "createdAtTimestamp": int(datetime.now(timezone.utc).timestamp()),
                                "updatedAtTimestamp": int(datetime.now(timezone.utc).timestamp()),
                                "sourceCreatedAtTimestamp": message.get('internalDate'),
                                "sourceLastModifiedTimestamp": message.get('internalDate'),
                                "externalRecordId": None,
                                "recordSource": "CONNECTOR",
                                "connectorName": "GOOGLE_GMAIL",
                                "isArchived": False,
                                "lastSyncTime": int(datetime.now(timezone.utc).timestamp()),
                                "indexingStatus": "NOT_STARTED",
                                "extractionStatus": "NOT_STARTED"
                            }

                            messages.append(message_record)
                            records.append(record)
                            logger.debug(
                                "✅ Message record created: %s", message_record)

                            # Create PARENT_CHILD relationship in thread if not first message
                            if previous_message_key:
                                logger.debug(
                                    "🔗 Creating PARENT_CHILD relation between messages in thread")
                                recordRelations.append({
                                    '_from': f'records/{previous_message_key}',
                                    '_to': f'records/{message_record["_key"]}',
                                    'relationType': 'SIBLING',
                                })

                            # Update previous message key for next iteration
                            previous_message_key = message_record['_key']

                    # Process attachments
                    logger.debug("📎 Processing %d attachments",
                                 len(attachments_metadata))
                    for attachment in attachments_metadata:
                        print("attachment: ", type(attachment))
                        attachment_id = attachment['attachment_id']
                        message_id = attachment.get('message_id')
                        logger.debug(
                            "📎 Processing attachment %s for message %s", attachment_id, message_id)

                        # Check if attachment exists
                        logger.debug(
                            "🔍 Checking if attachment %s exists in ArangoDB", attachment_id)
                        existing_attachment = self.arango_service.db.aql.execute(
                            'FOR doc IN attachments FILTER doc.externalAttachmentId == @attachment_id RETURN doc',
                            bind_vars={'attachment_id': attachment_id}
                        )
                        existing_attachment = next(existing_attachment, None)

                        if existing_attachment:
                            logger.debug(
                                "♻️ Attachment %s already exists in ArangoDB", attachment_id)
                            existing_attachments.append(attachment_id)
                        else:
                            logger.debug(
                                "➕ Creating new attachment record for %s", attachment_id)
                            attachment_record = {
                                '_key': str(uuid.uuid4()),
                                'externalAttachmentId': attachment_id,
                                'messageId': message_id,
                                'mimeType': attachment.get('mimeType'),
                                'filename': attachment.get('filename'),
                                'size': attachment.get('size'),
                                'webUrl': f"https://mail.google.com/mail?authuser={{user.email}}#all/{message_id}",
                                'lastSyncTime': int(datetime.now(timezone.utc).timestamp())
                            }
                            record = {
                                "_key": attachment_record['_key'],
                                "recordName": "placeholder",
                                "recordType": "attachment",
                                "version": 0,
                                "createdAtTimestamp": int(datetime.now(timezone.utc).timestamp()),
                                "updatedAtTimestamp": int(datetime.now(timezone.utc).timestamp()),
                                "sourceCreatedAtTimestamp": attachment.get('internalDate'),
                                "sourceLastModifiedTimestamp": attachment.get('internalDate'),
                                "externalRecordId": None,
                                "recordSource": "CONNECTOR",
                                "connectorName": "GOOGLE_GMAIL",
                                "isArchived": False,
                                "lastSyncTime": int(datetime.now(timezone.utc).timestamp()),
                                "indexingStatus": "NOT_STARTED",
                                "extractionStatus": "NOT_STARTED"
                            }
                            attachments.append(attachment_record)
                            records.append(record)
                            logger.debug(
                                "✅ Attachment record created: %s", attachment_record)

                            # Create record relation
                            message_key = next(
                                (m['_key'] for m in messages if m['externalMessageId'] == message_id), None)
                            if message_key:
                                logger.debug(
                                    "🔗 Creating relation between message %s and attachment %s", message_id, attachment_id)
                                recordRelations.append({
                                    '_from': f'records/{message_key}',
                                    '_to': f'records/{attachment_record["_key"]}',
                                    'relationType': 'attachment'
                                })
                            else:
                                logger.warning(
                                    "⚠️ Could not find message key for attachment relation: %s -> %s", message_id, attachment_id)

                    logger.debug("🔒 Processing permissions")
                    for permission in permissions_metadata:
                        message_id = permission.get('messageId')
                        attachment_ids = permission.get('attachmentIds', [])
                        emails = permission.get('users', [])
                        role = permission.get('role')
                        logger.debug(
                            "🔐 Processing permission for message %s, users/groups %s", message_id, emails)

                        # Get the correct message_key from messages based on messageId
                        message_key = next(
                            (m['_key'] for m in messages if m['externalMessageId'] == message_id), None)
                        if message_key:
                            logger.debug(
                                "🔗 Creating relation between users/groups and message %s", message_id)
                            for email in emails:
                                entity_id = await self.arango_service.get_entity_id_by_email(email)
                                if entity_id:
                                    # Check if entity exists in users or groups
                                    if self.arango_service.db.collection(CollectionNames.USERS.value).has(entity_id):
                                        entityType = CollectionNames.USERS.value
                                    elif self.arango_service.db.collection(CollectionNames.GROUPS.value).has(entity_id):
                                        entityType = CollectionNames.GROUPS.value
                                    else:
                                        # Save entity in people collection
                                        entityType = CollectionNames.PEOPLE.value
                                        await self.arango_service.save_to_people_collection(entity_id, email)

                                    permissions.append({
                                        '_from': f'{entityType}/{entity_id}',
                                        '_to': f'messages/{message_key}',
                                        'relationType': 'HAS_ACCESS',
                                        'role': role
                                    })
                        else:
                            logger.warning(
                                "⚠️ Could not find message key for permission relation: message %s", message_id)

                        # Process permissions for attachments
                        for attachment_id in attachment_ids:
                            logger.debug(
                                "🔗 Processing permission for attachment %s", attachment_id)
                            attachment_key = next(
                                (a['_key'] for a in attachments if a['externalAttachmentId'] == attachment_id), None)
                            if attachment_key:
                                logger.debug(
                                    "🔗 Creating relation between users/groups and attachment %s", attachment_id)
                                for email in emails:
                                    entity_id = await self.arango_service.get_entity_id_by_email(email)
                                    if entity_id:
                                        # Check if entity exists in users or groups
                                        if self.arango_service.db.collection(CollectionNames.USERS.value).has(entity_id):
                                            entityType = CollectionNames.USERS.value
                                        elif self.arango_service.db.collection(CollectionNames.GROUPS.value).has(entity_id):
                                            entityType = CollectionNames.GROUPS.value
                                        else:
                                            logger.warning(
                                                "⚠️ Entity %s not found in users or groups, skipping", entity_id)
                                            continue

                                        permissions.append({
                                            '_from': f'{entityType}/{entity_id}',
                                            '_to': f'attachments/{attachment_key}',
                                            'relationType': 'HAS_ACCESS',
                                            'role': role
                                        })
                            else:
                                logger.warning(
                                    "⚠️ Could not find attachment key for permission relation: attachment %s", attachment_id)

                # Batch process all collected data
                logger.info("📊 Batch summary before processing:")
                logger.info("- New messages to create: %d", len(messages))
                logger.info("- New attachments to create: %d",
                            len(attachments))
                logger.info("- New relations to create: %d",
                            len(recordRelations))
                logger.info("- Existing messages skipped: %d",
                            len(existing_messages))
                logger.info("- Existing attachments skipped: %d",
                            len(existing_attachments))

                if messages or attachments:
                    try:
                        logger.debug("🔄 Starting database transaction")
                        txn = None
                        txn = self.arango_service.db.begin_transaction(
                            read=[CollectionNames.MAILS.value, CollectionNames.ATTACHMENTS.value,
                                  CollectionNames.RECORDS.value, CollectionNames.RECORD_RELATIONS.value, CollectionNames.PERMISSIONS.value],
                            write=[CollectionNames.MAILS.value, CollectionNames.ATTACHMENTS.value,
                                   CollectionNames.RECORDS.value, CollectionNames.RECORD_RELATIONS.value, CollectionNames.PERMISSIONS.value]
                        )

                        if messages:
                            logger.debug(
                                "📥 Upserting %d messages", len(messages))
                            if not await self.arango_service.batch_upsert_nodes(messages, collection=CollectionNames.MAILS.value, transaction=txn):
                                raise Exception(
                                    "Failed to batch upsert messages")
                            logger.debug("✅ Messages upserted successfully")

                        if attachments:
                            logger.debug(
                                "📥 Upserting %d attachments", len(attachments))
                            if not await self.arango_service.batch_upsert_nodes(attachments, collection=CollectionNames.ATTACHMENTS.value, transaction=txn):
                                raise Exception(
                                    "Failed to batch upsert attachments")
                            logger.debug("✅ Attachments upserted successfully")
                            
                        if records:
                            logger.debug(
                                "📥 Upserting %d records", len(records))
                            if not await self.arango_service.batch_upsert_nodes(records, collection=CollectionNames.RECORDS.value, transaction=txn):
                                raise Exception(
                                    "Failed to batch upsert records")
                            logger.debug("✅ Records upserted successfully")

                        if recordRelations:
                            logger.debug(
                                "🔗 Creating %d record relations", len(recordRelations))
                            if not await self.arango_service.batch_create_edges(recordRelations, collection=CollectionNames.RECORD_RELATIONS.value, transaction=txn):
                                raise Exception(
                                    "Failed to batch create relations")
                            logger.debug(
                                "✅ Record relations created successfully")

                        if permissions:
                            logger.debug(
                                "🔗 Creating %d permissions", len(permissions))
                            if not await self.arango_service.batch_create_edges(permissions, collection=CollectionNames.PERMISSIONS.value, transaction=txn):
                                raise Exception(
                                    "Failed to batch create permissions")
                            logger.debug("✅ Permissions created successfully")

                        logger.debug("✅ Committing transaction")
                        txn.commit_transaction()

                        txn = None

                        processing_time = datetime.now(
                            timezone.utc) - batch_start_time
                        logger.info("""
                        ✅ Batch processed successfully:
                        - Messages: %d
                        - Attachments: %d
                        - Relations: %d
                        - Processing Time: %s
                        """, len(messages), len(attachments), len(recordRelations), processing_time)

                        return True

                    except Exception as e:
                        if txn:
                            logger.error(
                                "❌ Transaction failed, rolling back: %s", str(e))
                            txn.abort_transaction()
                        logger.error(
                            "❌ Failed to process batch data: %s", str(e))
                        return False

                logger.info(
                    "✅ Batch processing completed with no new data to process")
                return True

        except Exception as e:
            logger.error("❌ Batch processing failed with error: %s", str(e))
            return False


class GmailSyncEnterpriseService(BaseGmailSyncService):
    """Sync service for enterprise setup using admin service"""

    def __init__(
        self,
        config: ConfigurationService,
        gmail_admin_service: GmailAdminService,
        arango_service: ArangoService,
        change_handler: GmailChangeHandler,
        kafka_service: KafkaService,
        celery_app
    ):
        super().__init__(config, arango_service, kafka_service, celery_app)
        self.gmail_admin_service = gmail_admin_service

    async def connect_services(self) -> bool:
        """Connect to services for enterprise setup"""
        try:
            logger.info("🚀 Connecting to enterprise services")

            # Connect to Google Drive Admin
            if not await self.gmail_admin_service.connect_admin():
                raise Exception("Failed to connect to Drive Admin API")

            logger.info("✅ Enterprise services connected successfully")
            return True

        except Exception as e:
            logger.error("❌ Enterprise service connection failed: %s", str(e))
            return False

    async def initialize(self) -> bool:
        """Initialize enterprise sync service"""
        try:
            logger.info("🚀 Initializing")
            if not await self.connect_services():
                return False

            users = []
            groups = []

            # List and store enterprise users
            source_users = await self.gmail_admin_service.list_enterprise_users()
            for user in source_users:
                if not await self.arango_service.get_entity_id_by_email(user['email']):
                    logger.info("New user Found!")
                    users.append(user)

            if users:
                logger.info("🚀 Found %s users", len(users))
                await self.arango_service.batch_upsert_nodes(users, collection=CollectionNames.USERS.value)

            # List and store groups
            source_groups = await self.gmail_admin_service.list_groups()
            for group in source_groups:
                if not await self.arango_service.get_entity_id_by_email(group['email']):
                    logger.info("New group Found!")
                    groups.append(group)

            if groups:
                logger.info("🚀 Found %s groups", len(groups))
                await self.arango_service.batch_upsert_nodes(groups, collection=CollectionNames.GROUPS.value)

            organization_name = await self.config.get_config('organization')
            if not await self.arango_service.organization_exists(organization_name):
                organization = {
                    '_key': str(uuid.uuid4()),
                    'name': organization_name
                }
                logger.info("🚀 Organization: %s", organization)
                await self.arango_service.batch_upsert_nodes([organization], collection=CollectionNames.ORGS.value)

            # Create relationships between users and groups in belongsTo collection
            belongs_to_group_relations = []
            for group in groups:
                try:
                    # Get group members for each group
                    group_members = await self.gmail_admin_service.list_group_members(group['email'])

                    for member in group_members:
                        # Find the matching user
                        matching_user = next(
                            (user for user in users if user['email'] == member['email']), None)

                        if matching_user:
                            relation = {
                                '_from': f'users/{matching_user["_key"]}',
                                '_to': f'groups/{group["_key"]}',
                                'entityType': 'GROUP',
                                'role': member.get('role', 'member')
                            }
                            belongs_to_group_relations.append(relation)

                except Exception as e:
                    logger.error(
                        "❌ Error fetching group members for group %s: %s", group['_key'], str(e))

            # Batch insert belongsTo group relations
            if belongs_to_group_relations:
                await self.arango_service.batch_create_edges(belongs_to_group_relations, collection=CollectionNames.BELONGS_TO.value)
                logger.info("✅ Created %s user-group relationships",
                            len(belongs_to_group_relations))

            # Create relationships between users and orgs in belongsTo collection
            belongs_to_org_relations = []
            for user in users:
                relation = {
                    '_from': f'users/{user["_key"]}',
                    '_to': f'organizations/{organization["_key"]}',
                    'entityType': 'ORGANIZATION'
                }
                belongs_to_org_relations.append(relation)

            if belongs_to_org_relations:
                await self.arango_service.batch_create_edges(belongs_to_org_relations, collection=CollectionNames.BELONGS_TO.value)
                logger.info("✅ Created %s user-organization relationships",
                            len(belongs_to_org_relations))

            await self.celery_app.setup_app()

            # Set up changes watch for each user
            for user in users:
                try:
                    sync_state = await self.arango_service.get_user_sync_state(user['email'], 'gmail')
                    current_state = sync_state.get('syncState') if sync_state else 'NOT_STARTED'
                    if current_state == 'RUNNING':
                        logger.warning(f"Sync is currently RUNNING for user {user['email']}. Pausing it.")
                        await self.arango_service.update_user_sync_state(
                            user['email'],
                            'PAUSED',
                            service_type='gmail'
                        )

                    # Set up changes watch for the user
                    logger.info("👀 Setting up changes watch for all users...")
                    channel_data = await self.gmail_admin_service.create_user_watch(user['email'])
                    if not channel_data:
                        logger.warning(
                            "❌ Failed to set up changes watch for user: %s", user['email'])
                        continue

                    logger.info(
                        "✅ Changes watch set up successfully for user: %s", user['email'])

                    logger.info("🚀 Channel data: %s", channel_data)
                    await self.arango_service.store_channel_history_id(channel_data, user['email'])

                except Exception as e:
                    logger.error(
                        "❌ Error setting up changes watch for user %s: %s", user['email'], str(e))

            logger.info("✅ Sync service initialized successfully")
            return True

        except Exception as e:
            logger.error("❌ Failed to initialize enterprise sync: %s", str(e))
            return False

    async def perform_initial_sync(self, org_id, action: str = "start", resume_state: Dict = None) -> bool:
        """First phase: Build complete gmail structure"""
        try:
            # Add global stop check at the start
            if await self._should_stop():
                logger.info("Sync stopped before starting")
                return False

            users = await self.arango_service.get_users(org_id=org_id)

            for user in users:
                
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'RUNNING',
                    service_type='gmail'
                )

                # Stop checks
                if await self._should_stop():
                    logger.info(
                        "Sync stopped during user %s processing", user['email'])
                    await self.arango_service.update_user_sync_state(
                        user['email'],
                        'PAUSED',
                        service_type='gmail'
                    )
                    return False

                # Initialize user service
                user_service = await self.gmail_admin_service.create_user_service(user['email'])
                if not user_service:
                    logger.warning(
                        "❌ Failed to create user service for user: %s", user['email'])
                    continue

                # List all threads for the user
                threads = await user_service.list_threads()
                messages_list = await user_service.list_messages()
                messages_full = []
                attachments = []
                permissions = []
                for message in messages_list:
                    message_data = await user_service.get_message(message['id'])
                    messages_full.append(message_data)

                for message in messages_full:
                    attachments_for_message = await user_service.list_attachments(message['id'])
                    attachments.extend(attachments_for_message)
                    attachment_ids = [attachment['id']
                                      for attachment in attachments_for_message]
                    headers = message.get("headers", {})
                    permissions.append({
                        'messageId': message['id'],
                        'attachmentIds': attachment_ids,
                        'role': 'reader',
                        'users': [
                            headers.get("To", []),
                            headers.get("From", []),
                            headers.get("Cc", []),
                            headers.get("Bcc", [])
                        ]
                    })

                if not threads:
                    logger.info(f"No threads found for user {user['email']}")
                    continue

                self.progress.total_files = len(threads) + len(messages_full)
                logger.info("🚀 Total threads: %s", len(threads))
                # logger.debug(f"Threads: {threads}")
                logger.info("🚀 Total messages: %s", len(messages_full))
                # logger.debug(f"Messages: {messages_full}")
                logger.info("🚀 Total permissions: %s", len(permissions))
                logger.debug(f"Permissions: {permissions}")

                # Process threads in batches
                batch_size = 50
                start_batch = 0

                for i in range(start_batch, len(threads), batch_size):
                    # Stop check before each batch
                    if await self._should_stop():
                        logger.info(
                            f"Sync stopped during batch processing at index {i}")
                        # Save current state before stopping
                        return False

                    batch = threads[i:i + batch_size]
                    logger.info(
                        "🚀 Processing batch of %s threads starting at index %s", len(batch), i)
                    batch_metadata = []

                    # Process each thread in batch
                    for thread in batch:
                        thread_messages = []
                        thread_attachments = []

                        current_thread_messages = [
                            m for m in messages_full if m.get('threadId') == thread['id']
                        ]

                        if not current_thread_messages:
                            logger.warning(
                                "❌ 1. No messages found for thread %s", thread['id'])
                            continue

                        logger.info("📨 Found %s messages in thread %s", len(
                            current_thread_messages), thread['id'])

                        # Process each message
                        for message in current_thread_messages:
                            message_attachments = await user_service.list_attachments(message['id'])
                            if message_attachments:
                                logger.debug("📎 Found %s attachments in message %s", len(
                                    message_attachments), message['id'])
                                thread_attachments.extend(message_attachments)

                            # Add message with its attachments
                            thread_messages.append({
                                'message': message,
                                'attachments': message_attachments
                            })

                        # Prepare complete thread metadata
                        metadata = {
                            'thread': thread,
                            'thread_id': thread['id'],
                            'messages': thread_messages,
                            'attachments': thread_attachments,
                            'permissions': permissions
                        }

                        logger.info("✅ Completed thread %s processing: %s messages, %s attachments", thread['id'], len(
                            thread_messages), len(thread_attachments))
                        batch_metadata.append(metadata)

                    logger.info(
                        "✅ Completed batch processing: %s threads", len(batch_metadata))

                    # Process the batch metadata
                    if not await self.process_batch(batch_metadata):
                        logger.warning(
                            "Failed to process batch starting at index %s", i)
                        continue

                    # Send events to Kafka for the batch
                    for metadata in batch_metadata:
                        for message_data in metadata['messages']:
                            message = message_data['message']
                            message_key = await self.arango_service.get_key_by_external_message_id(message['id'])
                            
                            headers = message.get('headers', {})
                            message_event = {
                                "orgId": org_id,
                                "recordId": message_key,
                                "recordName": headers.get('Subject', 'No Subject'),
                                "recordType": "MESSAGE",
                                "recordVersion": 0,
                                "eventType": "create",
                                "body": message.get('body', ''),
                                "signedUrlRoute": f"http://localhost:8080/api/v1/gmail/record/{message_key}/signedUrl",
                                "metadataRoute": f"/api/v1/gmail/record/{message_key}/metadata",
                                "connectorName": "GOOGLE_GMAIL",
                                "recordSource": "CONNECTOR",
                                "mimeType": "text/gmail_content",
                                "threadId": metadata['thread']['id'],
                                "createdAtSourceTimestamp": int(message.get('internalDate', datetime.now(timezone.utc).timestamp())),
                                "modifiedAtSourceTimestamp": int(message.get('internalDate', datetime.now(timezone.utc).timestamp()))
                            }
                            await self.kafka_service.send_event_to_kafka(message_event)
                            logger.info("📨 Sent Kafka Indexing event for message %s", message_key)

                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'COMPLETED',
                    service_type='gmail'
                )

            # Add completion handling
            self.is_completed = True
            await self._complete_sync(status="COMPLETED")
            return True

        except Exception as e:
            if 'user' in locals():
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'FAILED',
                    service_type='gmail'
                )
            logger.error(f"❌ Initial sync failed: {str(e)}")
            return False

    async def sync_specific_user(self, user_email: str) -> bool:
        """Synchronize a specific user's Gmail content"""
        try:
            logger.info("🚀 Starting sync for specific user: %s", user_email)

            # Verify user exists in the database
            sync_state = await self.arango_service.get_user_sync_state(user_email, 'gmail')
            current_state = sync_state.get('syncState') if sync_state else 'NOT_STARTED'
            if current_state == 'RUNNING':
                logger.warning("💥 Gmail sync is already running for user %s", user_email)
                return False

            # Update user sync state to RUNNING
            await self.arango_service.update_user_sync_state(
                user_email,
                'RUNNING',
                'gmail'
            )
            
            user_id = await self.arango_service.get_entity_id_by_email(user_email)
            query = f"""
            FOR edge IN belongsTo
                FILTER edge._from == 'users/{user_id}'
                AND edge.entityType == 'ORGANIZATION'
                RETURN PARSE_IDENTIFIER(edge._to).key
            """
            cursor = self.arango_service.db.aql.execute(query)
            org_id = next(cursor, None)
            
            if not org_id:
                logger.warning(f"No organization found for user {user_email}")
                return False


            # Create user service instance
            user_service = await self.gmail_admin_service.create_user_service(user_email)
            if not user_service:
                logger.error("❌ Failed to create Gmail service for user %s", user_email)
                await self.arango_service.update_user_sync_state(user_email, 'FAILED', 'gmail')
                return False

            # Set up changes watch for the user
            channel_data = await self.gmail_admin_service.create_user_watch(user_email)
            if not channel_data:
                logger.error("❌ Failed to set up changes watch for user: %s", user_email)
                await self.arango_service.update_user_sync_state(user_email, 'FAILED', 'gmail')
                return False

            # Store channel data
            await self.arango_service.store_channel_history_id(channel_data, user_email)

            # List all threads and messages
            threads = await user_service.list_threads()
            messages_list = await user_service.list_messages()
            
            if not threads:
                logger.info("No threads found for user %s", user_email)
                await self.arango_service.update_user_sync_state(user_email, 'COMPLETED', 'gmail')
                return True

            # Process messages and build full metadata
            messages_full = []
            attachments = []
            permissions = []

            for message in messages_list:
                message_data = await user_service.get_message(message['id'])
                messages_full.append(message_data)

                # Get attachments for message
                attachments_for_message = await user_service.list_attachments(message_data)
                attachments.extend(attachments_for_message)
                attachment_ids = [attachment['attachment_id'] for attachment in attachments_for_message]
                
                # Build permissions from message headers
                headers = message_data.get("headers", {})
                permissions.append({
                    'messageId': message['id'],
                    'attachmentIds': attachment_ids,
                    'role': 'reader',
                    'users': [
                        headers.get("To", []),
                        headers.get("From", []),
                        headers.get("Cc", []),
                        headers.get("Bcc", [])
                    ]
                })

            # Process threads in batches
            batch_size = 50
            for i in range(0, len(threads), batch_size):
                if await self._should_stop():
                    logger.info("Sync stopped during batch processing at index %s", i)
                    await self.arango_service.update_user_sync_state(user_email, 'PAUSED', 'gmail')
                    return False

                batch = threads[i:i + batch_size]
                batch_metadata = []

                # Process each thread in batch
                for thread in batch:
                    thread_messages = []
                    thread_attachments = []

                    # Get messages for this thread
                    current_thread_messages = [
                        m for m in messages_full if m.get('threadId') == thread['id']
                    ]

                    if not current_thread_messages:
                        logger.warning("❌ No messages found for thread %s", thread['id'])
                        continue

                    # Process messages in thread
                    for message in current_thread_messages:
                        message_attachments = await user_service.list_attachments(message)
                        if message_attachments:
                            thread_attachments.extend(message_attachments)
                        thread_messages.append({'message': message})

                    # Add thread metadata
                    metadata = {
                        'thread': thread,
                        'threadId': thread['id'],
                        'messages': thread_messages,
                        'attachments': thread_attachments,
                        'permissions': permissions
                    }
                    batch_metadata.append(metadata)

                # Process batch
                if not await self.process_batch(batch_metadata):
                    logger.warning("Failed to process batch starting at index %s", i)
                    continue

                # Send events to Kafka
                for metadata in batch_metadata:
                    # Message events
                    for message_data in metadata['messages']:
                        message = message_data['message']
                        message_key = await self.arango_service.get_key_by_external_message_id(message['id'])
                        
                        headers = message.get('headers', {})
                        message_event = {
                            "orgId": org_id,
                            "recordId": message_key,
                            "recordName": headers.get('Subject', 'No Subject'),
                            "recordType": "MESSAGE",
                            "recordVersion": 0,
                            "eventType": "create",
                            "body": message.get('body', ''),
                            "signedUrlRoute": f"http://localhost:8080/api/v1/gmail/record/{message_key}/signedUrl",
                            "metadataRoute": f"/api/v1/gmail/record/{message_key}/metadata",
                            "connectorName": "GOOGLE_GMAIL",
                            "recordSource": "CONNECTOR",
                            "mimeType": "text/gmail_content",
                            "threadId": metadata['thread']['id'],
                            "createdAtSourceTimestamp": int(message.get('internalDate', datetime.now(timezone.utc).timestamp())),
                            "modifiedAtSourceTimestamp": int(message.get('internalDate', datetime.now(timezone.utc).timestamp()))
                        }
                        await self.kafka_service.send_event_to_kafka(message_event)
                        logger.info("📨 Sent Kafka Indexing event for message %s", message_key)

            # Update user state to COMPLETED
            await self.arango_service.update_user_sync_state(user_email, 'COMPLETED', 'gmail')
            logger.info("✅ Successfully completed sync for user %s", user_email)
            return True

        except Exception as e:
            await self.arango_service.update_user_sync_state(user_email, 'FAILED', 'gmail')
            logger.error("❌ Failed to sync user %s: %s", user_email, str(e))
            return False


class GmailSyncIndividualService(BaseGmailSyncService):
    """Sync service for individual user setup"""

    def __init__(
        self,
        config: ConfigurationService,
        gmail_user_service: GmailUserService,
        arango_service: ArangoService,
        change_handler: GmailChangeHandler,
        kafka_service: KafkaService,
        celery_app
    ):
        super().__init__(config, arango_service, kafka_service, celery_app)
        self.gmail_user_service = gmail_user_service

    async def connect_services(self) -> bool:
        """Connect to services for individual setup"""
        try:
            logger.info("🚀 Connecting to individual user services")

            # Connect to Google Drive
            if not await self.gmail_user_service.connect_individual_user():
                raise Exception("Failed to connect to Gmail API")

            # Connect to ArangoDB
            if not await self.arango_service.connect():
                raise Exception("Failed to connect to ArangoDB")

            logger.info("✅ Individual user services connected successfully")
            return True
        except Exception as e:
            logger.error("❌ Individual service connection failed: %s", str(e))
            return False

    async def initialize(self) -> bool:
        """Initialize individual user sync service"""
        try:
            if not await self.connect_services():
                return False

            # Get and store user info with initial sync state
            user_info = await self.gmail_user_service.list_individual_user()
            logger.info("🚀 User Info: %s", user_info)
            if user_info:
                # Add sync state to user info                
                user_id = await self.arango_service.get_entity_id_by_email(user_info[0]['email'])
                if not user_id:
                    await self.arango_service.batch_upsert_nodes(user_info, collection=CollectionNames.USERS.value)
                user_info = user_info[0]

            # Create user watch
            channel_data = await self.gmail_user_service.create_user_watch()

            # Initialize Celery
            await self.celery_app.setup_app()

            # Check if sync is already running
            sync_state = await self.arango_service.get_user_sync_state(user_info['email'], 'gmail')
            current_state = sync_state.get('syncState') if sync_state else 'NOT_STARTED'
            if current_state == 'RUNNING':
                logger.warning(f"Gmail sync is currently RUNNING for user {user_info['email']}. Pausing it.")
                await self.arango_service.update_user_sync_state(
                    user_info['email'],
                    'PAUSED',
                    'gmail'
                )
            await self.arango_service.store_channel_history_id(channel_data, user_info['email'])

            logger.info("✅ Gmail sync service initialized successfully")
            return True

        except Exception as e:
            logger.error("❌ Failed to initialize individual Gmail sync: %s", str(e))
            return False

    async def perform_initial_sync(self, org_id, action: str = "start") -> bool:
        """First phase: Build complete gmail structure"""
        try:
            if await self._should_stop():
                logger.info("Sync stopped before starting")
                return False

            user = await self.gmail_user_service.list_individual_user()
            user = user[0]

            # Update user sync state to RUNNING
            await self.arango_service.update_user_sync_state(
                user['email'],
                'RUNNING',
                'gmail'
            )

            if await self._should_stop():
                logger.info("Sync stopped during user %s processing", user['email'])
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'PAUSED',
                    'gmail'
                )
                return False

            # Initialize user service
            user_service = self.gmail_user_service

            # List all threads and messages for the user
            threads = await user_service.list_threads()
            messages_list = await user_service.list_messages()
            messages_full = []
            attachments = []
            permissions = []

            if not threads:
                logger.info(f"No threads found for user {user['email']}")
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'COMPLETED',
                    'gmail'
                )
                return False

            # Process messages
            for message in messages_list:
                message_data = await user_service.get_message(message['id'])
                messages_full.append(message_data)

            for message in messages_full:
                attachments_for_message = await user_service.list_attachments(message)
                attachments.extend(attachments_for_message)
                attachment_ids = [attachment['attachment_id'] for attachment in attachments_for_message]
                headers = message.get("headers", {})
                
                permissions.append({
                    'messageId': message['id'],
                    'attachmentIds': attachment_ids,
                    'role': 'reader',
                    'users': [
                        headers.get("To", []),
                        headers.get("From", []),
                        headers.get("Cc", []),
                        headers.get("Bcc", [])
                    ]
                })

            # Process threads in batches
            batch_size = 50
            start_batch = 0

            for i in range(start_batch, len(threads), batch_size):
                if await self._should_stop():
                    logger.info(f"Sync stopped during batch processing at index {i}")
                    await self.arango_service.update_user_sync_state(
                        user['email'],
                        'PAUSED',
                        'gmail'
                    )
                    return False

                batch = threads[i:i + batch_size]
                batch_metadata = []

                # Process each thread in batch
                for thread in batch:
                    thread_messages = []
                    thread_attachments = []

                    current_thread_messages = [
                        m for m in messages_full if m.get('threadId') == thread['id']
                    ]

                    if not current_thread_messages:
                        logger.warning(f"❌ 2. No messages found for thread {thread['id']}")
                        continue

                    # Process messages in thread
                    for message in current_thread_messages:
                        message_attachments = await user_service.list_attachments(message)
                        if message_attachments:
                            thread_attachments.extend(message_attachments)
                        thread_messages.append({'message': message})

                    # Add thread metadata
                    metadata = {
                        'thread': thread,
                        'threadId': thread['id'],
                        'messages': thread_messages,
                        'attachments': thread_attachments,
                        'permissions': permissions
                    }
                    batch_metadata.append(metadata)

                # Process batch
                if not await self.process_batch(batch_metadata):
                    logger.warning(f"Failed to process batch starting at index {i}")
                    continue

                # Send events to Kafka for threads, messages and attachments
                logger.info("🚀 Preparing events for Kafka for batch %s", i)
                for metadata in batch_metadata:   
                    # Message events
                    for message_data in metadata['messages']:
                        message = message_data['message']
                        message_key = await self.arango_service.get_key_by_external_message_id(message['id'])
                        # message = await self.arango_service.get_document(message_key, "messages")

                        headers = message.get('headers', {})
                        message_event = {
                            "orgId": org_id,
                            "recordId": message_key,
                            "recordName": headers.get('Subject', 'No Subject'),
                            "recordType": "MESSAGE",
                            "recordVersion": 0,
                            "eventType": "create",
                            "body": message.get('body', ''),
                            "signedUrlRoute": f"http://localhost:8080/api/v1/gmail/record/{message_key}/signedUrl",
                            "metadataRoute": f"/api/v1/gmail/record/{message_key}/metadata",
                            "connectorName": "GOOGLE_GMAIL",
                            "recordSource": "CONNECTOR",
                            "mimeType": "text/gmail_content",
                            "threadId": metadata['thread']['id'],
                            "createdAtSourceTimestamp": int(message.get('internalDate', datetime.now(timezone.utc).timestamp())),
                            "modifiedAtSourceTimestamp": int(message.get('internalDate', datetime.now(timezone.utc).timestamp()))
                        }
                        await self.kafka_service.send_event_to_kafka(message_event)
                        logger.info(
                            "📨 Sent Kafka Indexing event for message %s", message_key)

                    # # Attachment events
                    # for attachment in metadata['attachments']:
                    #     attachment_event = {
                    #         "recordId": attachment['attachment_id'],
                    #         "recordName": attachment.get('filename', 'Unnamed Attachment'),
                    #         "recordType": "attachment",
                    #         "recordVersion": 0,
                    #         'eventType': "create",
                    #         "metadataRoute": f"/api/v1/gmail/attachments/{attachment['attachment_id']}/metadata",
                    #         "signedUrlRoute": f"http://localhost:8080/api/v1/gmail/attachments/{attachment['attachment_id']}/signedUrl",
                    #         "connectorName": "GOOGLE_GMAIL",
                    #         "recordSource": "CONNECTOR",
                    #         "mimeType": attachment.get('mimeType', 'application/octet-stream'),
                    #         "size": attachment.get('size', 0),
                    #         "messageId": attachment.get('message_id'),
                    #         "threadId": metadata['thread']['id'],
                    #         "createdAtSourceTimestamp": int(datetime.now(timezone.utc).timestamp()),
                    #         "modifiedAtSourceTimestamp": int(datetime.now(timezone.utc).timestamp())
                    #     }
                    #     await self.kafka_service.send_event_to_kafka(attachment_event)

            # Update user state to COMPLETED
            await self.arango_service.update_user_sync_state(
                user['email'],
                'COMPLETED',
                'gmail'
            )

            self.is_completed = True
            return True

        except Exception as e:
            if 'user' in locals():
                await self.arango_service.update_user_sync_state(
                    user['email'],
                    'FAILED',
                    'gmail'
                )
            logger.error(f"❌ Initial sync failed: {str(e)}")
            return False
