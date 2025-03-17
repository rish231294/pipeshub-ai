import { Container } from 'inversify';
import { Logger } from '../../../libs/services/logger.service';
import { AppConfig } from '../../tokens_manager/config/config';
import { MongoService } from '../../../libs/services/mongo.service';
import { ArangoService } from '../../../libs/services/arango.service';
import { ConfigurationManagerConfig } from '../../configuration_manager/config/config';
import { KeyValueStoreService } from '../../../libs/services/keyValueStore.service';
import { RecordsEventProducer } from '../services/records_events.service';
import { EncryptionService } from '../../../libs/encryptor/encryptor';
import { configPaths } from '../../configuration_manager/paths/paths';
import { AuthTokenService } from '../../../libs/services/authtoken.service';
import { AuthMiddleware } from '../../../libs/middlewares/auth.middleware';
import { configTypes } from '../../../libs/utils/config.utils';

const loggerConfig = {
  service: 'Knowledge Base Service',
};

export class KnowledgeBaseContainer {
  private static instance: Container;
  private static logger: Logger = Logger.getInstance(loggerConfig);

  static async initialize(
    appConfig: AppConfig,
    configurationManagerConfig: ConfigurationManagerConfig,
  ): Promise<Container> {
    const container = new Container();
    this.logger.info(' In the init  kb conatiner');
    // Bind configuration
    container.bind<AppConfig>('AppConfig').toConstantValue(appConfig);
    // Bind logger
    container.bind<Logger>('Logger').toConstantValue(this.logger);
    container
      .bind<ConfigurationManagerConfig>('ConfigurationManagerConfig')
      .toConstantValue(configurationManagerConfig);

    // Initialize and bind services
    await this.initializeServices(container);

    this.instance = container;
    return container;
  }

  private static async initializeServices(container: Container): Promise<void> {
    try {
      // Initialize services
      const mongoService = new MongoService();
      await mongoService.initialize();
      container
        .bind<MongoService>('MongoService')
        .toConstantValue(mongoService);

      const arangoService = new ArangoService();
      await arangoService.initialize();
      container
        .bind<ArangoService>('ArangoService')
        .toConstantValue(arangoService);

      const configurationManagerConfig =
        container.get<ConfigurationManagerConfig>('ConfigurationManagerConfig');
      const keyValueStoreService = KeyValueStoreService.getInstance(
        configurationManagerConfig,
      );
      await keyValueStoreService.connect();
      container
        .bind<KeyValueStoreService>('KeyValueStoreService')
        .toConstantValue(keyValueStoreService);

      const encryptedKafkaConfig = await keyValueStoreService.get<string>(
        configPaths.broker.kafka,
      );

      const kafkaConfig = JSON.parse(
        EncryptionService.getInstance(
          configurationManagerConfig.algorithm,
          configurationManagerConfig.secretKey,
        ).decrypt(encryptedKafkaConfig),
      );
      this.logger.info('before events producer');

      const recordsEventProducer = new RecordsEventProducer(
        kafkaConfig,
        this.logger,
      );

      // Start the Kafka producer
      await recordsEventProducer.start();

      container
        .bind<RecordsEventProducer>('RecordsEventProducer')
        .toConstantValue(recordsEventProducer);

      this.logger.info('After events producer binding');

      const jwtSecret = await keyValueStoreService.get<string>(
        configTypes.JWT_SECRET,
      );
      const scopedJwtSecret = await keyValueStoreService.get<string>(
        configTypes.SCOPED_JWT_SECRET,
      );
      const authTokenService = new AuthTokenService(
        jwtSecret || ' ',
        scopedJwtSecret || ' ',
      );
      const authMiddleware = new AuthMiddleware(
        container.get('Logger'),
        authTokenService,
      );
      container
        .bind<AuthMiddleware>('AuthMiddleware')
        .toConstantValue(authMiddleware);
      this.logger.info('Knowledge Base services initialized successfully');
    } catch (error) {
      this.logger.error('Failed to initialize Knowledge Base services', {
        error: error instanceof Error ? error.message : 'Unknown error',
      });
      throw error;
    }
  }

  static getInstance(): Container {
    if (!this.instance) {
      throw new Error('Service container not initialized');
    }
    return this.instance;
  }

  static async dispose(): Promise<void> {
    if (this.instance) {
      try {
        // Stop the Kafka producer
        if (this.instance.isBound('RecordsEventProducer')) {
          const recordsEventProducer = this.instance.get<RecordsEventProducer>(
            'RecordsEventProducer',
          );
          await recordsEventProducer.stop();
        }

        // Handle other services
        const services = this.instance.getAll<any>('Service');
        for (const service of services) {
          if (typeof service.disconnect === 'function') {
            await service.disconnect();
          }
        }

        this.instance = null!;
        this.logger.info('All services successfully disposed');
      } catch (error) {
        this.logger.error('Error during service disposal', {
          error: error instanceof Error ? error.message : 'Unknown error',
        });
      }
    }
  }
}
