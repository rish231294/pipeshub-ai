import { ConfigService } from '../services/cm.service';

export interface AppConfig {
  jwtSecret: string;
  scopedJwtSecret: string;
  cookieSecret: string;
  rsAvailable: string;
  encryption: {
    key: string;
    algorithm: string;
  };
  communicationBackend: string;
  frontendUrl: string;
  iamBackend: string;
  authUrl: string;
  cmUrl: string;
  kafka: {
    clientId: string;
    brokers: string[];
    groupId: string;
    sasl?: {
      mechanism: 'plain' | 'scram-sha-256' | 'scram-sha-512';
      username: string;
      password: string;
    };
  };
  redis: {
    host: string;
    port: number;
    password?: string;
    db?: number;
  };
  mongo: {
    uri: string;
    dbName: string;
  };

  qdrant: {
    apiKey: string;
    host: string;
    gprc_port: number;
  };

  arango: {
    url: string;
    dbName: string;
    username: string;
    password: string;
  };
  etcd: {
    host: string;
    port: number;
    dialTimeout: number;
  };

  smtp: {
    host: string;
    port: number;
    username?: string;
    password?: string;
    fromEmail: string;
  };
  storage: {
    storageType: string;
    endpoint: string;
  };
  notification: {
    notificationUrl: string;
  };
}

export const loadAppConfig = async (): Promise<AppConfig> => {
  const configService = ConfigService.getInstance();
  const commonBackendUrl = await configService.getCommonBackendUrl();

  return {
    jwtSecret: configService.getJwtSecret(),
    scopedJwtSecret: configService.getScopedJwtSecret(),
    cookieSecret: configService.getCookieSecret(),
    rsAvailable: configService.getRsAvailable(),
    encryption: {
      key: process.env.SECRET_KEY!,
      algorithm: 'aes-256-gcm',
    },
    frontendUrl: await configService.getFrontendUrl(),
    communicationBackend: commonBackendUrl,
    iamBackend: commonBackendUrl,
    authUrl: commonBackendUrl,
    cmUrl: commonBackendUrl,
    notification: {
      notificationUrl: commonBackendUrl,
    },
    kafka: await configService.getKafkaConfig(),
    redis: await configService.getRedisConfig(),
    arango: await configService.getArangoConfig(),
    qdrant: await configService.getQdrantConfig(),
    mongo: await configService.getMongoConfig(),
    smtp: await configService.getSmtpConfig(),
    etcd: {
      host: process.env.ETCD_HOST!,
      port: parseInt(process.env.ETCD_PORT!, 10),
      dialTimeout: parseInt(process.env.ETCD_DIAL_TIMEOUT!, 10),
    },
    storage: await configService.getStorageConfig(),
  };
};
