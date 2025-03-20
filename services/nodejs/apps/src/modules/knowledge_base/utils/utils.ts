import { Readable } from 'stream';
import FormData from 'form-data';
import { AuthenticatedUserRequest } from '../../../libs/middlewares/types';
import { Logger } from '../../../libs/services/logger.service';
import { FileBufferInfo } from '../../../libs/middlewares/file_processor/fp.interface';
import axios from 'axios';
import { KeyValueStoreService } from '../../../libs/services/keyValueStore.service';
import { storageEtcdPaths } from '../../storage/constants/constants';
import { HTTP_STATUS } from '../../../libs/enums/http-status.enum';
import {
  DefaultNotificationConfig,
  DefaultStorageConfig,
} from '../../tokens_manager/services/cm.service';
import { NotificationCommand } from '../../../libs/commands/notification/notification.command';
import { NOTIFICATION_EVENTS } from '../../notification/constants/constants';

const logger = Logger.getInstance({
  service: 'knowledge_base.utils',
});

const axiosInstance = axios.create({
  maxRedirects: 0,
});

export interface StorageResponseMetadata {
  documentId: string;
  documentName: string;
}

export const saveFileToStorageAndGetDocumentId = async (
  req: AuthenticatedUserRequest,
  file: FileBufferInfo,
  documentName: string,
  isVersionedFile: boolean,
  keyValueStoreService: KeyValueStoreService,
  defaultConfig: DefaultStorageConfig,
  notificationConfig: DefaultNotificationConfig,
): Promise<StorageResponseMetadata> => {
  const formData = new FormData();

  // Add the file with proper metadata
  formData.append('file', file.buffer, {
    filename: file.originalname,
    contentType: file.mimetype,
  });
  const storageUrl =
    (await keyValueStoreService.get(storageEtcdPaths.endpoint)) ||
    defaultConfig.endpoint;

  // Add other required fields
  formData.append(
    'documentPath',
    `PipesHub/KnowledgeBase/${req.user?.userId}/${documentName}`,
  );
  formData.append('isVersionedFile', isVersionedFile.toString());
  formData.append('documentName', getFilenameWithoutExtension(documentName));

  try {
    const response = await axiosInstance.post(
      `${storageUrl}/api/v1/document/upload`,
      formData,
      {
        headers: {
          ...formData.getHeaders(),
          Authorization: req.headers.authorization,
        },
      },
    );

    return {
      documentId: response.data?._id,
      documentName: response.data?.documentName,
    };
  } catch (error: any) {
    if (error.response.status === HTTP_STATUS.PERMANENT_REDIRECT) {
      const redirectUrl = error.response.headers.location;
      logger.info('Redirecting to storage url', { redirectUrl });

      // Extract document information from headers
      const documentId = error.response.headers['x-document-id'];
      const documentName = error.response.headers['x-document-name'];

      runInBackGround(
        req.user?.userId,
        file.buffer,
        redirectUrl,
        documentId,
        documentName,
        req.headers.authorization,
        notificationConfig,
      );
      return { documentId, documentName };
    } else {
      logger.error('Error uploading file to storage', {
        error: error.response.data,
      });
      throw error;
    }
  }
};

function runInBackGround(
  userId: string,
  buffer: Buffer,
  redirectUrl: string,
  documentId: string,
  documentName: string,
  authToken: string | undefined,
  notificationConfig: DefaultNotificationConfig,
) {
  // Start the upload in the background
  logger.info('Starting background upload', {
    userId,
    documentId,
    documentName,
  });
  (async () => {
    try {
      // Create a readable stream from the buffer
      const bufferStream = new Readable();
      bufferStream.push(buffer);
      bufferStream.push(null); // Signal end of stream

      // Start the upload but don't await it
      axios({
        method: 'put',
        url: redirectUrl,
        data: bufferStream,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Length': buffer.length,
        },
        maxContentLength: Infinity,
        maxBodyLength: Infinity,
      })
        .then((response) => {
          // TODO: Notify the user about the upload completion
          sendNotificationToUser(
            userId,
            documentId,
            documentName,
            response.status,
            authToken,
            notificationConfig,
          );
          logger.info('Background upload completed successfully', {
            documentId,
            documentName,
            status: response.status,
          });
        })
        .catch((uploadError) => {
          // TODO: Notify the user about the upload failure
          sendNotificationToUser(
            userId,
            documentId,
            documentName,
            uploadError.status,
            authToken,
            notificationConfig,
          );
          logger.error('Background upload failed', {
            documentId,
            documentName,
            error: uploadError.message,
          });
        });
    } catch (error: any) {
      logger.error('Error setting up background upload', {
        documentId,
        documentName,
        error: error.message,
      });
    }
  })();
}

export const uploadNextVersionToStorage = async (
  req: AuthenticatedUserRequest,
  file: FileBufferInfo,
  documentId: string,
  keyValueStoreService: KeyValueStoreService,
  defaultConfig: DefaultStorageConfig,
): Promise<StorageResponseMetadata> => {
  const formData = new FormData();

  // Add the file with proper metadata
  formData.append('file', file.buffer, {
    filename: file.originalname,
    contentType: file.mimetype,
  });

  const storageUrl =
    (await keyValueStoreService.get(storageEtcdPaths.endpoint)) ||
    defaultConfig.endpoint;

  try {
    const response = await axiosInstance.post(
      `${storageUrl}/api/v1/document/${documentId}/uploadNextVersion`,
      formData,
      {
        headers: {
          ...formData.getHeaders(),
          Authorization: req.headers.authorization,
        },
      },
    );

    return {
      documentId: response.data?._id,
      documentName: response.data?.documentName,
    };
  } catch (error: any) {
    logger.error('Error uploading file to storage', error.response.message);
    throw error;
  }
};

function getFilenameWithoutExtension(originalname: string) {
  const fileExtension = originalname.slice(originalname.lastIndexOf('.') + 1);
  return originalname.slice(0, -fileExtension.length - 1);
}

async function sendNotificationToUser(
  userId: string,
  documentId: string,
  documentName: string,
  status: number,
  authToken: string | undefined,
  notificationConfig: DefaultNotificationConfig,
) {
  const notificationCommand = new NotificationCommand({
    uri: `${notificationConfig.notificationUrl}/api/v1/notifications/notify/user/${userId}`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${authToken}`,
    },
    body: {
      event: NOTIFICATION_EVENTS.FILE_UPLOAD_STATUS,
      data: {
        documentId,
        documentName,
        status,
      },
    },
  });
  try {
    const response = await notificationCommand.execute();
    logger.debug('Notification sent to user', {
      response,
    });
  } catch (error: any) {
    logger.error('Error sending notification to user', {
      error: error.message,
    });
    // do nothing, notification is not critical
  }
}
