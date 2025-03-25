
from dependency_injector import containers, providers
from app.config.configuration_service import ConfigurationService, config_node_constants
from arango import ArangoClient
from app.modules.retrieval.retrieval_service import RetrievalService
from app.modules.retrieval.retrieval_arango import ArangoService
from app.utils.logger import logger

class AppContainer(containers.DeclarativeContainer):
    """Dependency injection container for the application."""
    # Log when container is initialized
    logger.info("🚀 Initializing AppContainer")

    # Initialize ConfigurationService first
    config_service = providers.Singleton(
        ConfigurationService,
        environment='dev'
    )
    
    async def _fetch_arango_host(config_service):
        """Fetch ArangoDB host URL from etcd asynchronously."""
        return await config_service.get_config(config_node_constants.ARANGO_URL.value)

    async def _create_arango_client(config_service):
        """Async factory method to initialize ArangoClient."""
        hosts = await AppContainer._fetch_arango_host(config_service)
        return ArangoClient(hosts=hosts)

    arango_client = providers.Resource(
        _create_arango_client, config_service=config_service)

    # First create an async factory for the connected ArangoService
    async def _create_arango_service(arango_client, config):
        """Async factory to create and connect ArangoService"""
        print("arango client: ", arango_client)
        service = ArangoService(arango_client, config)
        await service.connect()
        return service

    arango_service = providers.Resource(
        _create_arango_service,
        arango_client=arango_client,
        config=config_service
    )

    # Vector search service
    async def _get_qdrant_config(config_service: ConfigurationService):
        """Async factory method to get Qdrant configuration."""
        return {
            'collection_name': await config_service.get_config(config_node_constants.QDRANT_COLLECTION_NAME.value),
            'api_key': await config_service.get_config(config_node_constants.QDRANT_API_KEY.value),
            'host': await config_service.get_config(config_node_constants.QDRANT_HOST.value),
            'port': await config_service.get_config(config_node_constants.QDRANT_PORT.value),
        }

    qdrant_config = providers.Resource(
        _get_qdrant_config,
        config_service=config_service
    )

    # Vector search service
    async def _create_retrieval_service(config):
        """Async factory for RetrievalService"""
        service = RetrievalService(
            collection_name=config['collection_name'],
            qdrant_api_key=config['api_key'],
            qdrant_host=config['host']
        )
        # Add any async initialization if needed
        return service

    retrieval_service = providers.Resource(
        _create_retrieval_service,
        config=qdrant_config
    )

