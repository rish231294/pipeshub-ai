"""Google Calendar Admin Service module for interacting with Google Calendar API"""

# pylint: disable=E1101, W0718
from typing import Dict, List, Optional
import os
from google.oauth2 import service_account
from googleapiclient.discovery import build
from app.config.configuration_service import ConfigurationService, config_node_constants
from app.connectors.google.gcal.core.gcal_user_service import GCalUserService
from app.utils.logger import logger
from app.connectors.utils.decorators import exponential_backoff
from app.connectors.utils.rate_limiter import GoogleAPIRateLimiter
from app.config.arangodb_constants import CollectionNames
from app.connectors.google.scopes import GOOGLE_CONNECTOR_ENTERPRISE_SCOPES


class GCalAdminService:
    """GCalAdminService class for interacting with Google Calendar API"""

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
                "❌ Failed to connect to Calendar Admin Service: %s", str(e))
            return False

    async def create_user_service(self, user_email: str) -> Optional[GCalUserService]:
        """Get or create a GCalUserService for a specific user"""
        try:
            # Create delegated credentials for the user
            user_credentials = self.credentials.with_subject(user_email)

            # Create new user service
            user_service = GCalUserService(
                config=self.config,
                rate_limiter=self.rate_limiter,
                credentials=user_credentials
            )

            # Connect the user service
            if not await user_service.connect_enterprise_user():
                return None

            return user_service

        except Exception as e:
            logger.error(f"❌ Failed to create user service for {
                         user_email}: {str(e)}")
            return None

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

                    current_users = results.get(CollectionNames.USERS.value, [])

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
