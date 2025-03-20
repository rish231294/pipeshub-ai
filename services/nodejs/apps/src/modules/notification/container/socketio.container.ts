import { Container } from 'inversify';
import { SocketIOService } from '../service/socketio.service';
import { AuthTokenService } from '../../../libs/services/authtoken.service';
import { AppConfig } from '../../tokens_manager/config/config';
import { TYPES } from '../../../libs/types/container.types';
export class SocketIOContainer {
  private static container: Container | null = null;

  static async initialize(appConfig: AppConfig): Promise<Container> {
    const container = new Container();
    const authTokenService = new AuthTokenService(
      appConfig.jwtSecret,
      appConfig.scopedJwtSecret,
    );
    container.bind<AuthTokenService>(TYPES.AuthTokenService).toConstantValue(authTokenService);
    container.bind(SocketIOService).toSelf().inSingletonScope();
    this.container = container;
    return container;
  }

  static async dispose(): Promise<void> {
    if (this.container) {
      this.container.unbindAll();
    }
  }
}