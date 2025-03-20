import { Router, Response, NextFunction } from 'express';
import { Container } from 'inversify';
import { ValidationMiddleware } from '../../../libs/middlewares/validation.middleware';
import { AuthMiddleware } from '../../../libs/middlewares/auth.middleware';
import {
  AuthenticatedUserRequest,
  AuthenticatedServiceRequest,
} from '../../../libs/middlewares/types';
import { extensionToMimeType } from '../mimetypes/mimetypes';
import { Logger } from '../../../libs/services/logger.service';
import { metricsMiddleware } from '../../../libs/middlewares/prometheus.middleware';
import {
  UploadNewSchema,
  DocumentIdParams,
  GetBufferSchema,
  CreateDocumentSchema,
  UploadNextVersionSchema,
  RollBackToPreviousVersionSchema,
  DirectUploadSchema,
  DocumentIdParamsWithVersion,
} from '../validators/validators';
import { KeyValueStoreService } from '../../../libs/services/keyValueStore.service';
import { FileProcessorFactory } from '../../../libs/middlewares/file_processor/fp.factory';
import { FileProcessingType } from '../../../libs/middlewares/file_processor/fp.constant';
import { TokenScopes } from '../../../libs/enums/token-scopes.enum';
import { StorageController } from '../controllers/storage.controller';

const logger = Logger.getInstance({ service: 'StorageRoutes' });

export function createStorageRouter(container: Container): Router {
  const router = Router();
  const keyValueStoreService = container.get<KeyValueStoreService>(
    'KeyValueStoreService',
  );
  const storageController =
    container.get<StorageController>('StorageController');
  const authMiddleware = container.get<AuthMiddleware>('AuthMiddleware');
  storageController.watchStorageType(keyValueStoreService);

  router.post(
    '/internal/upload',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ...FileProcessorFactory.createBufferUploadProcessor({
      fieldName: 'file',
      allowedMimeTypes: Object.values(extensionToMimeType),
      maxFilesAllowed: 1,
      isMultipleFilesAllowed: false,
      processingType: FileProcessingType.BUFFER,
      maxFileSize: 1024 * 1024 * 100,
      strictFileUpload: true,
    }).getMiddleware,
    ValidationMiddleware.validate(UploadNewSchema),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.uploadDocument(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  // Create a document placeholder and then client can upload the
  // document to the placeholder documentPath via direct upload api
  // provided by storage vendors

  router.post(
    '/internal/placeholder',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ValidationMiddleware.validate(CreateDocumentSchema),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.createPlaceholderDocument(
          req,
          res,
          next,
        );
      } catch (error) {
        next(error);
      }
    },
  );

  router.get(
    '/internal/:documentId',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ValidationMiddleware.validate(DocumentIdParams),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.getDocumentById(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  router.delete(
    '/internal/:documentId/',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ValidationMiddleware.validate(DocumentIdParams),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.deleteDocumentById(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  router.get(
    '/:documentId/download',
    authMiddleware.authenticate,
    metricsMiddleware(container),
    ValidationMiddleware.validate(DocumentIdParamsWithVersion),
    async (
      req: AuthenticatedUserRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.downloadDocument(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );
  router.get(
    '/internal/:documentId/download',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ValidationMiddleware.validate(DocumentIdParamsWithVersion),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.downloadDocument(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  // Document Operations Routes
  router.get(
    '/internal/:documentId/buffer',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ValidationMiddleware.validate(GetBufferSchema),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.getDocumentBuffer(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  router.put(
    '/internal/:documentId/buffer',
    authMiddleware.scopedTokenValidator(TokenScopes.STORAGE_TOKEN),
    metricsMiddleware(container),
    ...FileProcessorFactory.createBufferUploadProcessor({
      fieldName: 'file',
      allowedMimeTypes: Object.values(extensionToMimeType),
      maxFilesAllowed: 1,
      isMultipleFilesAllowed: false,
      processingType: FileProcessingType.BUFFER,
      maxFileSize: 1024 * 1024 * 100,
      strictFileUpload: true,
    }).getMiddleware,
    ValidationMiddleware.validate(DocumentIdParams),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.createDocumentBuffer(req, res, next);
      } catch (error: any) {
        logger.error(`Failed to upload buffer: ${error.message}`);
        next(error);
      }
    },
  );

  // Version Control Routes
  router.post(
    '/internal/:documentId/uploadNextVersion',
    authMiddleware.authenticate,
    ...FileProcessorFactory.createBufferUploadProcessor({
      fieldName: 'file',
      allowedMimeTypes: Object.values(extensionToMimeType),
      maxFilesAllowed: 1,
      isMultipleFilesAllowed: false,
      processingType: FileProcessingType.BUFFER,
      maxFileSize: 1024 * 1024 * 100,
      strictFileUpload: true,
    }).getMiddleware,
    metricsMiddleware(container),
    ValidationMiddleware.validate(UploadNextVersionSchema),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.uploadNextVersionDocument(
          req,
          res,
          next,
        );
      } catch (error) {
        next(error);
      }
    },
  );

  // Rollback to previous version
  router.post(
    '/internal/:documentId/rollBack',
    authMiddleware.authenticate,
    metricsMiddleware(container),
    ValidationMiddleware.validate(RollBackToPreviousVersionSchema),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.rollBackToPreviousVersion(
          req,
          res,
          next,
        );
      } catch (error) {
        next(error);
      }
    },
  );

  router.post(
    '/internal/:documentId/directUpload',
    authMiddleware.authenticate,
    metricsMiddleware(container),
    ValidationMiddleware.validate(DirectUploadSchema),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.uploadDirectDocument(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  router.get(
    '/internal/:documentId/isModified',
    authMiddleware.authenticate,
    metricsMiddleware(container),
    ValidationMiddleware.validate(DocumentIdParams),
    async (
      req: AuthenticatedServiceRequest,
      res: Response,
      next: NextFunction,
    ): Promise<void> => {
      try {
        return await storageController.documentDiffChecker(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  return router;
}
