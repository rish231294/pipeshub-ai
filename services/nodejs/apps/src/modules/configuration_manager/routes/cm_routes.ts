import { Router } from 'express';
import { Container } from 'inversify';
import { AuthMiddleware } from '../../../libs/middlewares/auth.middleware';
import {
  createAIModelsConfig,
  createGoogleWorkspaceCredentials,
  createKafkaConfig,
  createRedisConfig,
  createSmtpConfig,
  createStorageConfig,
  getAIModelsConfig,
  getAzureAdAuthConfig,
  getGoogleAuthConfig,
  getGoogleWorkspaceOauthConfig,
  getGoogleWorkspaceCredentials,
  getKafkaConfig,
  getMicrosoftAuthConfig,
  getRedisConfig,
  getSmtpConfig,
  getSsoAuthConfig,
  getStorageConfig,
  setAzureAdAuthConfig,
  setGoogleAuthConfig,
  setMicrosoftAuthConfig,
  setSsoAuthConfig,
  setGoogleWorkspaceOauthConfig,
  createArangoDbConfig,
  getArangoDbConfig,
  createMongoDbConfig,
  getMongoDbConfig,
} from '../controller/cm_controller';
import { KeyValueStoreService } from '../../../libs/services/keyValueStore.service';
import { ValidationMiddleware } from '../../../libs/middlewares/validation.middleware';
import {
  redisConfigSchema,
  smtpConfigSchema,
  kafkaConfigSchema,
  aiModelsConfigSchema,
  storageValidationSchema,
  azureAdConfigSchema,
  googleAuthConfigSchema,
  ssoConfigSchema,
  googleWorkspaceConfigSchema,
  mongoDBConfigSchema,
  arangoDBConfigSchema,
} from '../validator/validators';
import { FileProcessorFactory } from '../../../libs/middlewares/file_processor/fp.factory';
import { FileProcessingType } from '../../../libs/middlewares/file_processor/fp.constant';
import { metricsMiddleware } from '../../../libs/middlewares/prometheus.middleware';
import {
  checkArangoHealth,
  checkKafkaHealth,
  checkMongoHealth,
  checkRedisHealth,
} from '../middlewares/health.middleware';
import { EntitiesEventProducer } from '../../user_management/services/entity_events.service';
import { userAdminCheck } from '../../user_management/middlewares/userAdminCheck';
import { TokenScopes } from '../../../libs/enums/token-scopes.enum';

export function createConfigurationManagerRouter(container: Container): Router {
  const router = Router();
  const keyValueStoreService = container.get<KeyValueStoreService>(
    'KeyValueStoreService',
  );
  const eventService = container.get<EntitiesEventProducer>(
    'EntitiesEventProducer',
  );
  const authMiddleware = container.get<AuthMiddleware>('AuthMiddleware');
  // storage config routes

  /**
   * POST /storageConfig
   * Creates or updates storage configuration in the key-value store
   * Requires authentication
   * @param {Object} req.body.storageConfig - Storage configuration object to store
   * @returns {Object} The stored configuration object
   */
  router.post(
    '/storageConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(storageValidationSchema),
    createStorageConfig(keyValueStoreService),
  );

  /**
   * GET /storageConfig
   * Retrieves the current storage configuration from key-value store
   * Requires authentication
   * @returns {Object} The stored configuration object or null if not found
   */
  router.get(
    '/storageConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getStorageConfig(keyValueStoreService),
  );

  // SMTP Config Routes
  /**
   * POST /smtpConfig
   * Creates or updates SMTP configuration in the key-value store
   * Requires authentication
   * @param {Object} req.body.smtpConfig - SMTP configuration object to store
   * @returns {Object} The stored configuration object
   */
  router.post(
    '/smtpConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(smtpConfigSchema),
    createSmtpConfig(keyValueStoreService),
  );

  /**
   * GET /smtpConfig
   * Retrieves the current SMTP configuration from key-value store
   * Requires authentication
   * @returns {Object} The stored configuration object or null if not found
   */
  router.get(
    '/smtpConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getSmtpConfig(keyValueStoreService),
  );

  // auth config routes
  router.get(
    '/authConfig/azureAd',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getAzureAdAuthConfig(keyValueStoreService),
  );

  router.get(
    '/internal/authConfig/azureAd',
    authMiddleware.scopedTokenValidator(TokenScopes.FETCH_CONFIG),
    metricsMiddleware(container),
    getAzureAdAuthConfig(keyValueStoreService),
  );

  router.post(
    '/authConfig/azureAd',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(azureAdConfigSchema),
    setAzureAdAuthConfig(keyValueStoreService),
  );

  router.get(
    '/authConfig/microsoft',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getMicrosoftAuthConfig(keyValueStoreService),
  );
  router.get(
    '/internal/authConfig/microsoft',
    authMiddleware.scopedTokenValidator(TokenScopes.FETCH_CONFIG),
    metricsMiddleware(container),
    getMicrosoftAuthConfig(keyValueStoreService),
  );

  router.post(
    '/authConfig/microsoft',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(azureAdConfigSchema),
    setMicrosoftAuthConfig(keyValueStoreService),
  );

  router.get(
    '/authConfig/google',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getGoogleAuthConfig(keyValueStoreService),
  );

  router.get(
    '/internal/authConfig/google',
    authMiddleware.scopedTokenValidator(TokenScopes.FETCH_CONFIG),
    metricsMiddleware(container),
    getGoogleAuthConfig(keyValueStoreService),
  );
  router.post(
    '/authConfig/google',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(googleAuthConfigSchema),
    setGoogleAuthConfig(keyValueStoreService),
  );

  router.get(
    '/authConfig/sso',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getSsoAuthConfig(keyValueStoreService),
  );
  router.get(
    '/internal/authConfig/sso',
    authMiddleware.scopedTokenValidator(TokenScopes.FETCH_CONFIG),
    metricsMiddleware(container),
    getSsoAuthConfig(keyValueStoreService),
  );
  router.post(
    '/authConfig/sso',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(ssoConfigSchema),
    setSsoAuthConfig(keyValueStoreService),
  );

  router.post(
    '/mongoDBConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(mongoDBConfigSchema),
    checkMongoHealth,
    createMongoDbConfig(keyValueStoreService),
  );

  router.get(
    '/mongoDBConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getMongoDbConfig(keyValueStoreService),
  );

  router.post(
    '/arangoDBConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(arangoDBConfigSchema),
    checkArangoHealth,
    createArangoDbConfig(keyValueStoreService),
  );

  router.get(
    '/arangoDBConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getArangoDbConfig(keyValueStoreService),
  );

  // keyValueStore config routes
  /**
   * POST /keyValueStoreConfig
   * Creates or updates key-value store configuration in the key-value store
   * Requires authentication
   * @param {Object} req.body.keyValueStoreConfig - Key-value store configuration object to store
   * @returns {Object} The stored configuration object
   */
  router.post(
    '/redisConfig',
    authMiddleware.authenticate,
    metricsMiddleware(container),
    ValidationMiddleware.validate(redisConfigSchema),
    checkRedisHealth,
    createRedisConfig(keyValueStoreService),
  );

  /**
   * GET /keyValueStoreConfig
   * Retrieves the current key-value store configuration from key-value store
   * Requires authentication
   * @returns {Object} The stored configuration object or null if not found
   */
  router.get(
    '/redisConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getRedisConfig(keyValueStoreService),
  );

  // message broker config routes
  /**
   * POST /messageBrokerConfig
   * Creates or updates message broker configuration in the key-value store
   * Requires authentication
   * @param {Object} req.body.messageBrokerConfig - Message broker configuration object to store
   * @returns {Object} The stored configuration object
   */
  router.post(
    '/kafkaConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(kafkaConfigSchema),
    checkKafkaHealth,
    createKafkaConfig(keyValueStoreService),
  );

  /**
   * GET /messageBrokerConfig
   * Retrieves the current message broker configuration from key-value store
   * Requires authentication
   * @returns {Object} The stored configuration object or null if not found
   */
  router.get(
    '/kafkaConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getKafkaConfig(keyValueStoreService),
  );

  // Google Workspace Config Routes
  /**
   * POST /googleWorkspaceConfig
   * Creates or updates Google Workspace configuration in the key-value store
   * Requires authentication
   * @param {Object} req.body.googleWorkspaceConfig - Google Workspace configuration object to store
   * @returns {Object} The stored configuration object
   */
  router.post(
    '/connectors/googleWorkspaceCredentials',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ...FileProcessorFactory.createJSONUploadProcessor({
      fieldName: 'googleWorkspaceCredentials',
      allowedMimeTypes: ['application/json'],
      maxFilesAllowed: 1,
      isMultipleFilesAllowed: false,
      processingType: FileProcessingType.JSON,
      maxFileSize: 1024 * 1024 * 5,
      strictFileUpload: false,
    }).getMiddleware,
    createGoogleWorkspaceCredentials(keyValueStoreService),
  );

  /**
   * GET /googleWorkspaceConfig
   * Retrieves the current Google Workspace configuration from key-value store
   * Requires authentication
   * @returns {Object} The stored configuration object or null if not found
   */
  router.get(
    '/connectors/googleWorkspaceCredentials',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getGoogleWorkspaceCredentials(keyValueStoreService),
  );

  router.get(
    '/connectors/googleWorkspaceOauthConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getGoogleWorkspaceOauthConfig(keyValueStoreService),
  );

  router.post(
    '/connectors/googleWorkspaceOauthConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(googleWorkspaceConfigSchema),
    setGoogleWorkspaceOauthConfig(keyValueStoreService),
  );

  // ai models config routes
  /**
   * POST /aiModelsConfig
   * Creates or updates ai models configuration in the key-value store
   * Requires authentication
   * @param {Object} req.body.aiModelsConfig - Ai models configuration object to store
   * @returns {Object} The stored configuration object
   */
  router.post(
    '/aiModelsConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    ValidationMiddleware.validate(aiModelsConfigSchema),
    createAIModelsConfig(keyValueStoreService, eventService),
  );

  /**
   * GET /aiModelsConfig
   * Retrieves the current ai models configuration from key-value store
   * Requires authentication
   * @returns {Object} The stored configuration object or null if not found
   */
  router.get(
    '/aiModelsConfig',
    authMiddleware.authenticate,
    userAdminCheck,
    metricsMiddleware(container),
    getAIModelsConfig(keyValueStoreService),
  );

  return router;
}
