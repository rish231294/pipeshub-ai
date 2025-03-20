import { EncryptionService } from '../../../libs/encryptor/encryptor';
import { KeyValueStoreService } from '../../../libs/services/keyValueStore.service';
import { loadConfigurationManagerConfig } from '../../configuration_manager/config/config';
import { configPaths } from '../../configuration_manager/paths/paths';

// Define interfaces for all service configurations
export interface SmtpConfig {
  host: string;
  port: number;
  username?: string;
  password?: string;
  fromEmail: string;
}

export interface KafkaConfig {
  clientId: string;
  brokers: string[];
  groupId: string;
  sasl?: {
    mechanism: 'plain' | 'scram-sha-256' | 'scram-sha-512';
    username: string;
    password: string;
  };
}

export interface RedisConfig {
  host: string;
  port: number;
  password?: string;
  db?: number;
}

export interface MongoConfig {
  uri: string;
  dbName: string;
}

export interface QdrantConfig {
  apiKey: string;
  host: string;
  gprc_port: number;
}

export interface ArangoConfig {
  url: string;
  dbName: string;
  username: string;
  password: string;
}

export interface EtcdConfig {
  host: string;
  port: number;
  dialTimeout: number;
}

export interface EncryptionConfig {
  key: string;
  algorithm: string;
}

export interface DefaultStorageConfig {
  storageType: string;
  endpoint: string;
}

export interface DefaultNotificationConfig {
  notificationUrl: string;
}
// Main Config Service
export class ConfigService {
  private static instance: ConfigService;
  private keyValueStoreService: KeyValueStoreService;
  private configManagerConfig: any;
  private encryptionService: EncryptionService;

  private constructor() {
    this.configManagerConfig = loadConfigurationManagerConfig();
    this.keyValueStoreService = KeyValueStoreService.getInstance(
      this.configManagerConfig,
    );
    this.encryptionService = EncryptionService.getInstance(
      this.configManagerConfig.algorithm,
      this.configManagerConfig.secretKey,
    );
  }

  public static getInstance(): ConfigService {
    if (!ConfigService.instance) {
      ConfigService.instance = new ConfigService();
    }
    return ConfigService.instance;
  }

  public async connect(): Promise<void> {
    await this.keyValueStoreService.connect();
  }

  private async getEncryptedConfig<T>(
    configPath: string,
    fallbackEnvVars: Record<string, any>,
  ): Promise<T> {
    try {
      const encryptedConfig =
        await this.keyValueStoreService.get<string>(configPath);

      // If config exists in ETCD
      if (encryptedConfig) {
        return JSON.parse(this.encryptionService.decrypt(encryptedConfig)) as T;
      }
      const fallbackConfig = fallbackEnvVars as T;
      await this.saveConfigToEtcd(configPath, fallbackConfig);

      return fallbackConfig;
    } catch (error) {
      return fallbackEnvVars as T;
    }
  }

  // Save config to ETCD
  private async saveConfigToEtcd<T>(
    configPath: string,
    config: T,
  ): Promise<void> {
    try {
      // Encrypt the config before saving
      const encryptedConfig = this.encryptionService.encrypt(
        JSON.stringify(config),
      );

      // Save to key-value store
      await this.keyValueStoreService.set(configPath, encryptedConfig);
    } catch (error) {
      throw error;
    }
  }

  // SMTP Configuration
  public async getSmtpConfig(): Promise<SmtpConfig> {
    return this.getEncryptedConfig<SmtpConfig>(configPaths.smtp, {
      host: process.env.SMTP_HOST!,
      port: parseInt(process.env.SMTP_PORT || '587', 10),
      username: process.env.SMTP_USERNAME,
      password: process.env.SMTP_PASSWORD,
      fromEmail: process.env.SMTP_FROM_EMAIL!,
    });
  }

  // Kafka Configuration
  public async getKafkaConfig(): Promise<KafkaConfig> {
    return this.getEncryptedConfig<KafkaConfig>(configPaths.broker.kafka, {
      clientId: process.env.KAFKA_CLIENT_ID!,
      brokers: process.env.KAFKA_BROKERS!.split(','),
      groupId: process.env.KAFKA_GROUP_ID!,
      ...(process.env.KAFKA_USERNAME && {
        sasl: {
          mechanism: 'plain' as const,
          username: process.env.KAFKA_USERNAME,
          password: process.env.KAFKA_PASSWORD!,
        },
      }),
    });
  }

  // Redis Configuration
  public async getRedisConfig(): Promise<RedisConfig> {
    return this.getEncryptedConfig<RedisConfig>(
      configPaths.keyValueStore.redis,
      {
        host: process.env.REDIS_HOST!,
        port: parseInt(process.env.REDIS_PORT!, 10),
        password: process.env.REDIS_PASSWORD,
        db: parseInt(process.env.REDIS_DB || '0', 10),
      },
    );
  }

  // MongoDB Configuration
  public async getMongoConfig(): Promise<MongoConfig> {
    return this.getEncryptedConfig<MongoConfig>(configPaths.db.mongodb, {
      uri: process.env.MONGO_URI!,
      dbName: process.env.MONGO_DB_NAME!,
    });
  }

  // Qdrant Configuration
  public async getQdrantConfig(): Promise<QdrantConfig> {
    return this.getEncryptedConfig<QdrantConfig>(configPaths.db.qdrant, {
      apiKey: process.env.QDRANT_API_KEY!,
      host: process.env.QDRANT_HOST!,
      gprc_port: parseInt(process.env.QDRANT_GPRC_PORT || '6334', 10),
    });
  }

  // Arango Configuration
  public async getArangoConfig(): Promise<ArangoConfig> {
    return this.getEncryptedConfig<ArangoConfig>(configPaths.db.arangodb, {
      url: process.env.ARANGO_URL!,
      dbName: process.env.ARANGO_DB_NAME!,
      username: process.env.ARANGO_USERNAME!,
      password: process.env.ARANGO_PASSWORD!,
    });
  }

  // ETCD Configuration
  public async getEtcdConfig(): Promise<EtcdConfig> {
    return {
      host: process.env.ETCD_HOST!,
      port: parseInt(process.env.ETCD_PORT!, 10),
      dialTimeout: parseInt(process.env.ETCD_DIAL_TIMEOUT!, 10),
    };
  }

  // Get Common Backend URL
  public async getCommonBackendUrl(): Promise<string> {
    let url = await this.keyValueStoreService.get<string>(
      configPaths.url.privateEndpoint,
    );
    if (url === null) {
      url = process.env.NODE_COMMON_BACKEND ?? 'http://localhost:3000';
      await this.keyValueStoreService.set<string>(
        configPaths.url.privateEndpoint,
        url,
      );
    }
    return url;
  }
  public async getFrontendUrl(): Promise<string> {
    let url = await this.keyValueStoreService.get<string>(
      configPaths.url.publicEndpoint,
    );
    if (url === null) {
      url = process.env.FRONTEND_URL ?? 'http://localhost:3000';
      await this.keyValueStoreService.set<string>(
        configPaths.url.publicEndpoint,
        url,
      );
    }
    return url;
  }
  public async getStorageConfig(): Promise<DefaultStorageConfig> {
    let endpoint = await this.keyValueStoreService.get<string>(
      configPaths.storageService.endpoint,
    );
    let storageType = await this.keyValueStoreService.get<string>(
      configPaths.storageService.storageType,
    );
    if (endpoint === null) {
      endpoint = process.env.STORAGE_ENDPOINT ?? 'http://localhost:3000';
      await this.keyValueStoreService.set<string>(
        configPaths.storageService.endpoint,
        endpoint,
      );
    }
    if (storageType === null) {
      storageType = process.env.STORAGE_TYPE ?? 'local';
      await this.keyValueStoreService.set<string>(
        configPaths.storageService.storageType,
        storageType,
      );
    }
    return { storageType, endpoint };
  }

  // Get JWT Secret
  public getJwtSecret(): string {
    return process.env.JWT_SECRET!;
  }

  // Get Scoped JWT Secret
  public getScopedJwtSecret(): string {
    return process.env.SCOPED_JWT_SECRET!;
  }

  public getCookieSecret(): string {
    return process.env.COOKIE_SECRET!;
  }

  public getRsAvailable(): string {
    return process.env.REPLICA_SET_AVAILABLE!;
  }
}
