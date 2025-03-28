"""Gmail Admin Service module for interacting with Google GMail API"""

# pylint: disable=E1101, W0718
import os
from typing import Dict, List, Optional
from google.oauth2 import service_account
from googleapiclient.discovery import build
from app.config.configuration_service import ConfigurationService, config_node_constants
from app.connectors.google.gmail.core.gmail_user_service import GmailUserService
from app.utils.logger import logger
from app.connectors.utils.decorators import exponential_backoff
from app.connectors.utils.rate_limiter import GoogleAPIRateLimiter
from app.connectors.google.scopes import GOOGLE_CONNECTOR_ENTERPRISE_SCOPES


class GmailAdminService:
    """GmailAdminService class for interacting with Google GMail API"""

    def __init__(self, config: ConfigurationService, rate_limiter: GoogleAPIRateLimiter):
        self.config = config
        self.rate_limiter = rate_limiter
        self.google_limiter = self.rate_limiter.google_limiter
        self.admin_service = None
        self.credentials = None

    async def connect_admin(self) -> bool:
        """Initialize admin service with domain-wide delegation"""
        try:
            SCOPES = GOOGLE_CONNECTOR_ENTERPRISE_SCOPES
            service_account_path = await self.config.get_config(config_node_constants.GOOGLE_AUTH_SERVICE_ACCOUNT_PATH.value)
            admin_email = await self.config.get_config(config_node_constants.GOOGLE_AUTH_ADMIN_EMAIL.value)

            self.credentials = service_account.Credentials.from_service_account_file(
                service_account_path,
                scopes=SCOPES,
                subject=admin_email
            )

            self.admin_service = build(
                'admin',
                'directory_v1',
                credentials=self.credentials,
                cache_discovery=False
            )

            return True

        except Exception as e:
            logger.error(
                "❌ Failed to connect to Drive Admin Service: %s", str(e))
            return False

    @exponential_backoff()
    async def list_enterprise_users(self) -> List[Dict]:
        """List all users in the domain for enterprise setup"""
        try:
            logger.info("🚀 Listing domain users")
            users = []
            page_token = None

            while True:
                async with self.google_limiter:
                    results = self.admin_service.users().list(
                        customer='my_customer',
                        orderBy='email',
                        projection='full',
                        pageToken=page_token
                    ).execute()

                    current_users = results.get('users', [])
                    logger.info("USERS: %s", current_users)

                    users.extend([{
                        '_key': user.get('id'),
                        'email': user.get('primaryEmail'),
                        'domain': user.get('primaryEmail', '').split('@')[-1] if user.get('primaryEmail') else None,
                        'fullName': user.get('name', {}).get('fullName'),
                        'designation': user.get('designation', 'user'),
                        'isActive': False,
                        'createdAt': user.get('creationTime'),
                    } for user in current_users if not user.get('suspended', False)])

                    page_token = results.get('nextPageToken')
                    if not page_token:
                        break

            logger.info("✅ Found %s active users in domain", len(users))
            return users

        except Exception as e:
            logger.error("❌ Failed to list domain users: %s", str(e))
            return []

    async def create_user_service(self, user_email: str) -> Optional[GmailUserService]:
        """Get or create a GmailUserService for a specific user"""
        try:
            # Create delegated credentials for the user
            user_credentials = self.credentials.with_subject(user_email)

            # Create new user service
            user_service = GmailUserService(
                config=self.config,
                rate_limiter=self.rate_limiter,
                credentials=user_credentials
            )

            # Connect the user service
            if not await user_service.connect_enterprise_user():
                return None

            return user_service

        except Exception as e:
            logger.error(
                "❌ Failed to create user service for %s: %s", user_email, str(e))
            return None

    @exponential_backoff()
    async def list_groups(self) -> List[Dict]:
        """List all groups in the domain for enterprise setup"""
        try:
            logger.info("🚀 Listing domain groups")
            groups = []
            page_token = None

            while True:
                async with self.google_limiter:
                    results = self.admin_service.groups().list(
                        customer='my_customer',
                        pageToken=page_token
                    ).execute()

                    current_groups = results.get('groups', [])

                    groups.extend([{
                        '_key': group.get('id'),
                        'groupId': group.get('id'),
                        'groupName': group.get('name'),
                        'email': group.get('email'),
                        'description': group.get('description', ''),
                        'adminCreated': group.get('adminCreated', False),
                        'createdAt': group.get('creationTime'),
                    } for group in current_groups])

                    page_token = results.get('nextPageToken')
                    if not page_token:
                        break

            logger.info("✅ Found %s groups", len(groups))
            return groups

        except Exception as e:
            logger.error("❌ Failed to list groups: %s", str(e))
            return []

    @exponential_backoff()
    async def list_domains(self) -> List[Dict]:
        """List all domains for the enterprise"""
        try:
            logger.info("🚀 Listing domains")
            domains = []
            page_token = None

            while True:
                async with self.google_limiter:
                    results = self.admin_service.domains().list(
                        customer='my_customer',
                    ).execute()

                    current_domains = results.get('domains', [])

                    domains.extend([{
                        '_key': f"gdr_domain_{domain.get('domainName')}",
                        'domainName': domain.get('domainName'),
                        'verified': domain.get('verified', False),
                        'isPrimary': domain.get('isPrimary', False),
                        'createdAt': domain.get('creationTime'),
                    } for domain in current_domains])

                    page_token = results.get('nextPageToken')
                    if not page_token:
                        break

            logger.info("✅ Found %s domains", len(domains))
            return domains

        except Exception as e:
            logger.error("❌ Failed to list domains: %s", str(e))
            return []

    @exponential_backoff()
    async def list_group_members(self, group_email: str) -> List[Dict]:
        """List all members of a specific group"""
        try:
            logger.info(f"🚀 Listing members for group: {group_email}")
            members = []
            page_token = None

            while True:
                async with self.google_limiter:
                    results = self.admin_service.members().list(
                        groupKey=group_email,
                        pageToken=page_token
                    ).execute()

                    current_members = results.get('members', [])

                    members.extend([{
                        'email': member.get('email'),
                        'role': member.get('role', 'member').lower(),
                        'type': member.get('type'),
                        'status': member.get('status', 'active')
                    } for member in current_members])

                    page_token = results.get('nextPageToken')
                    if not page_token:
                        break

            logger.info(
                f"✅ Found {len(members)} members in group {group_email}")
            return members

        except Exception as e:
            logger.error(
                "❌ Failed to list group members for %s: %s", group_email, str(e))
            return []

    async def cleanup_user_service(self, user_email: str):
        """Cleanup user service when no longer needed"""
        if user_email in self._user_services:
            await self._user_services[user_email].disconnect()
            del self._user_services[user_email]

    async def create_user_watch(self, user_email) -> Dict:
        """Create user watch by impersonating the user"""
        try:
            logger.info("🚀 Creating user watch for user %s", user_email)
            topic = "projects/agile-seeker-447812-p3/topics/gmail-connector"

            # Create user-specific credentials using domain-wide delegation
            user_credentials = service_account.Credentials.from_service_account_file(
                await self.config.get_config(config_node_constants.GOOGLE_AUTH_SERVICE_ACCOUNT_PATH.value),
                scopes=['https://www.googleapis.com/auth/gmail.readonly'],
                subject=user_email
            )

            # Build Gmail service for the user
            gmail_service = build(
                'gmail', 'v1', credentials=user_credentials, cache_discovery=False)

            async with self.google_limiter:
                request_body = {
                    'labelIds': ['INBOX'],
                    'topicName': topic
                }
                response = gmail_service.users().watch(userId='me', body=request_body).execute()
                logger.info(
                    "✅ User watch created successfully for %s", user_email)
                return response
        except Exception as e:
            logger.error("❌ Failed to create user watch for %s: %s",
                         user_email, str(e))
            return {}
