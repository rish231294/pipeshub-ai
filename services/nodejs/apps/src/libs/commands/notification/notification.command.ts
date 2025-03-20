import { HttpMethod } from '../../enums/http-methods.enum';
import { BaseCommand } from '../command.interface';
import { Logger } from '../../services/logger.service';

const logger = Logger.getInstance({
  service: 'NotificationCommand',
});

export interface NotificationCommandOptions {
  uri: string;
  method: HttpMethod;
  headers?: Record<string, string>;
  queryParams?: Record<string, string | number | boolean>;
  // For methods that support a request body (PUT, POST, PATCH).
  body?: any;
}

export interface NotificationResponse {
  status: string;
  message: string;
}

export class NotificationCommand extends BaseCommand<NotificationResponse> {
  private method: HttpMethod;
  private body?: any;

  constructor(options: NotificationCommandOptions) {
    super(options.uri, options.queryParams, options.headers);
    this.method = options.method;
    this.body = this.sanitizeBody(options.body);
    this.headers = this.sanitizeHeaders(options.headers!);
  }

  // Execute the HTTP request based on the provided options.
  public async execute(): Promise<NotificationResponse> {
    logger.info('Notification command', {
      url: this.uri,
      method: this.method,
      headers: this.headers,
      body: this.body,
    });
    const url = this.buildUrl();
    const requestOptions: RequestInit = {
      method: this.method,
      headers: this.headers,
    };

    // If a body is provided by the caller, pass it as-is.
    if (this.body !== undefined) {
      requestOptions.body = this.body;
    }

    try {
      const response = await this.fetchWithRetry(
        async () => fetch(url, requestOptions),
        3,
        300,
      );

      logger.debug('Notification command response', {
        status: response.status,
        statusText: response.statusText,
        url: url,
        requestOptions: requestOptions,
      });

      // Assuming the response is JSON; adjust as needed.
      const data = await response.json();
      return {
        status: data.status,
        message: data.message,
      };
    } catch (error: any) {
      logger.error('Notification command failed', {
        error: error.message,
        url: url,
        requestOptions: requestOptions,
      });
      throw error;
    }
  }
}
