import { v4 as uuidv4 } from 'uuid';
import { AuthenticatedUserRequest } from './../../../libs/middlewares/types';
import { NextFunction, Response } from 'express';
import { Logger } from '../../../libs/services/logger.service';
import { RecordRelationService } from '../services/kb.relation.service';
import { IRecordDocument } from '../types/record';
import { IFileRecordDocument } from '../types/file_record';
import {
  BadRequestError,
  ForbiddenError,
  InternalServerError,
  NotFoundError,
  UnauthorizedError,
} from '../../../libs/errors/http.errors';
import {
  saveFileToStorageAndGetDocumentId,
  uploadNextVersionToStorage,
} from '../utils/utils';
import {
  INDEXING_STATUS,
  ORIGIN_TYPE,
  RECORD_TYPE,
  RELATIONSHIP_TYPE,
} from '../constants/record.constants';
import { KeyValueStoreService } from '../../../libs/services/keyValueStore.service';
import { configPaths } from '../../configuration_manager/paths/paths';
import { AppConfig } from '../../tokens_manager/config/config';
import { DefaultStorageConfig } from '../../tokens_manager/services/cm.service';

const logger = Logger.getInstance({
  service: 'Knowledge Base Controller',
});

export const createRecords =
  (
    recordRelationService: RecordRelationService,
    keyValueStoreService: KeyValueStoreService,
    appConfig: AppConfig,
  ) =>
  async (
    req: AuthenticatedUserRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      const files = req.body.fileBuffers;
      const userId = req.user?.userId;
      const orgId = req.user?.orgId;
      const { recordName } = req.body;
      const isVersioned = req.body?.isVersioned || true;

      if (!userId || !orgId) {
        throw new UnauthorizedError(
          'User not authenticated or missing organization ID',
        );
      }

      const currentTime = Date.now();

      // First ensure the user exists in the database
      const userDoc = await recordRelationService.findOrCreateUser(
        userId,
        req.user?.email || '',
        orgId,
        req.user?.firstName,
        req.user?.lastName,
        req.user?.middleName,
        req.user?.designation,
      );

      // Get or create a knowledge base for this organization
      const kb = await recordRelationService.getOrCreateKnowledgeBase(orgId);

      // Make sure the user has permission on this knowledge base
      await recordRelationService.createKbUserPermission(
        kb._key,
        userDoc._key,
        RELATIONSHIP_TYPE.USER,
        'OWNER',
      );

      const records: IRecordDocument[] = [];
      const fileRecords: IFileRecordDocument[] = [];

      // Process files
      for (const file of files) {
        const { originalname, mimetype, size } = file;
        const extension = originalname.includes('.')
          ? originalname
              .substring(originalname.lastIndexOf('.') + 1)
              .toLowerCase()
          : null;

        // Generate a unique ID for the record
        const key: string = uuidv4();

        const frontendUrl =
          (await keyValueStoreService.get<string>(
            configPaths.url.publicEndpoint,
          )) || appConfig.frontendUrl;

        const webUrl = `${frontendUrl}/knowledge-base/record/${key}`;

        // Get document ID from storage
        const { documentId, documentName } =
          await saveFileToStorageAndGetDocumentId(
            req,
            file,
            originalname,
            isVersioned,
            keyValueStoreService,
            appConfig.storage,
            appConfig.notification,
          );

        const record = {
          _key: key,
          orgId: orgId,
          recordName: recordName || documentName,
          externalRecordId: documentId,
          recordType: RECORD_TYPE.FILE,
          origin: ORIGIN_TYPE.UPLOAD,
          createdAtTimestamp: currentTime,
          updatedAtTimestamp: currentTime,
          isDeleted: false,
          isArchived: false,
          indexingStatus: INDEXING_STATUS.NOT_STARTED,
          version: 1,
        };
        records.push(record);

        // Prepare file record object
        fileRecords.push({
          _key: key,
          userId: userId,
          orgId: orgId,
          name: documentName,
          isFile: true,
          extension: extension,
          mimeType: mimetype,
          sizeInBytes: size,
          webUrl: webUrl,
        });
      }

      // Use the service method to insert records and file records in a transaction
      let result;
      try {
        result = await recordRelationService.insertRecordsAndFileRecords(
          records,
          fileRecords,
          keyValueStoreService,
        );
        logger.info(
          `Successfully inserted ${result.insertedRecords.length} records and file records`,
        );
      } catch (insertError) {
        logger.error('Failed to insert records and file records', {
          error: insertError,
        });
        throw new InternalServerError(
          insertError instanceof Error
            ? insertError.message
            : 'Unexpected error occurred',
        );
      }

      // Create relationships in a separate try-catch block
      try {
        // Now create relationships between entities
        for (let i = 0; i < result.insertedRecords.length; i++) {
          const recordId = result.insertedRecords[i]?._key;
          const fileRecordId = result.insertedFileRecords[i]?._key;

          // Create is_of_type relationship between record and file record
          if (recordId && fileRecordId) {
            await recordRelationService.createRecordToFileRecordRelationship(
              recordId,
              fileRecordId,
            );
          }

          // Add record to the knowledge base
          if (recordId) {
            await recordRelationService.addRecordToKnowledgeBase(
              kb._key,
              recordId,
            );
          }
        }

        logger.info(
          `Created relationships for ${result.insertedRecords.length} records`,
        );

        // Send the response after all operations succeed
        res.status(201).json({
          message: 'Records created successfully',
          data: {
            recordCount: result.insertedRecords.length,
            knowledgeBase: {
              id: kb._key,
              name: kb.name,
            },
            records: result.insertedRecords.map((record) => ({
              id: record._key,
              name: record.recordName,
              type: record.recordType,
            })),
          },
        });
      } catch (relationError: any) {
        // Handle relationship creation errors separately
        logger.error('Error creating relationships', { error: relationError });

        // Pass the error to the next middleware
        next(relationError);
      }
    } catch (error: any) {
      logger.error('Error creating records', { error });
      next(error);
    }
  };

export const getRecordById =
  (recordRelationService: RecordRelationService) =>
  async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
    try {
      const { recordId } = req.params as { recordId: string };
      const userId = req.user?.userId;
      const orgId = req.user?.orgId;

      if (!userId) {
        throw new BadRequestError('User not authenticated');
      }

      try {
        const recordData = await recordRelationService.getRecordById(
          recordId,
          userId,
          orgId,
        );

        res.status(200).json({
          ...recordData,
          meta: {
            requestId: req.context?.requestId,
            timestamp: new Date().toISOString(),
          },
        });
        return; // Added return statement
      } catch (error: any) {
        if (error.message?.includes('not found')) {
          throw new NotFoundError('Record not found');
        }

        if (error.message?.includes('does not have permission')) {
          throw new UnauthorizedError(
            'You do not have permission to access this record',
          );
        }

        throw error;
      }
    } catch (error: any) {
      logger.error('Error getting record by id', {
        recordId: req.params.recordId,
        error,
      });
      next(error);
      return; // Added return statement
    }
  };

/**
 * Update a record
 */

export const updateRecord =
  (
    recordRelationService: RecordRelationService,
    keyValueStoreService: KeyValueStoreService,
    defaultConfig: DefaultStorageConfig,
  ) =>
  async (
    req: AuthenticatedUserRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      const { recordId } = req.params as { recordId: string };
      const { userId, orgId } = req.user || {};
      const updateData = req.body || {};

      if (!userId || !orgId) {
        throw new BadRequestError('User authentication is required');
      }

      // Check if there's a file in the request
      const hasFileBuffer = req.body.fileBuffer && req.body.fileBuffer.buffer;
      let originalname, mimetype, size;

      if (hasFileBuffer) {
        ({ originalname, mimetype, size } = req.body.fileBuffer);
      }

      // Only check for empty updateData if there are no files
      if (Object.keys(updateData).length === 0 && !hasFileBuffer) {
        throw new BadRequestError('No update data or files provided');
      }

      // Check if user has permission to update records
      try {
        await recordRelationService.validateUserKbAccess(userId, orgId, [
          'OWNER','WRITER','FILEORGANIZER'
        ]);
      } catch (error) {
        throw new ForbiddenError('Permission denied');
      }

      // Get the current record to determine what's changing
      let existingRecord;
      try {
        existingRecord = await recordRelationService.getRecordById(
          recordId,
          userId,
          orgId,
        );

        if (!existingRecord || !existingRecord.record) {
          throw new NotFoundError(`Record with ID ${recordId} not found`);
        }
      } catch (error) {
        throw new NotFoundError(`Record with ID ${recordId} not found`);
      }

      // Expanded list of immutable fields based on record schema
      const immutableFields = [
        '_id',
        '_key',
        '_rev',
        'orgId',
        'userId',
        'createdAtTimestamp',
        'externalRecordId', // Generally shouldn't change
        'recordType', // Type shouldn't change after creation
        'origin', // Origin shouldn't change after creation
      ];

      const attemptedImmutableUpdates = immutableFields.filter(
        (field) => updateData[field] !== undefined,
      );

      if (attemptedImmutableUpdates.length > 0) {
        throw new BadRequestError(
          `Cannot update immutable fields: ${attemptedImmutableUpdates.join(', ')}`,
        );
      }

      // Prepare update data with timestamp
      const updatedData = {
        ...updateData,
        updatedAtTimestamp: Date.now(),
        isLatestVersion: true,
        sizeInBytes : size
      };


      // Handle file uploads if present
      let fileUploaded = false;
      let fileName = '';

      // Handle file uploads if we found files
      if (hasFileBuffer) {        

        // Use the externalRecordId as the storageDocumentId
        const storageDocumentId = existingRecord.record.externalRecordId;

        // Check if we have a valid externalRecordId to use
        if (!storageDocumentId) {
          throw new BadRequestError(
            'Cannot update file: No external record ID found for this record',
          );
        }

        fileName = originalname;
        // Get filename without extension to use as record name
        if (fileName && fileName.includes('.')) {
          const lastDotIndex = fileName.lastIndexOf('.');
          if (lastDotIndex > 0) {
            // Ensure there's a name part before the extension
            updatedData.recordName = fileName.substring(0, lastDotIndex);
            logger.info('Setting record name from file', {
              recordName: updatedData.recordName,
              originalFileName: fileName,
            });
          }
        }

        // Log the file upload
        logger.info('Uploading new version of file', {
          recordId,
          fileName: originalname,
          fileSize: size,
          mimeType: mimetype,
          storageDocumentId: storageDocumentId,
        });

        try {
          // Update version through storage service using externalRecordId
          const fileBuffer = req.body.fileBuffer;
          await uploadNextVersionToStorage(
            req,
            fileBuffer,
            storageDocumentId,
            keyValueStoreService,
            defaultConfig,
          );
          // Log the file upload
          logger.info('Uploading new version function called successfully');
          // Version will be auto-incremented in the service method
          // but we can explicitly set it here too
          updatedData.version = (existingRecord.record.version || 0) + 1;
          fileUploaded = true;
        } catch (storageError: any) {
          logger.error('Failed to upload file to storage', {
            recordId,
            storageDocumentId: storageDocumentId,
            error: storageError.message,
          });
          throw new InternalServerError(
            `Failed to upload file: ${storageError.message}`,
          );
        }
      }
      // Handle soft delete case
      if (updatedData.isDeleted === true && !existingRecord.record.isDeleted) {
        updatedData.deletedByUserId = userId;
        updatedData.deletedAtTimestamp = Date.now();

        // If this is a file, mark it as no longer latest version
        if (existingRecord.record.recordType === 'FILE') {
          updatedData.isLatestVersion = false;
        }

        logger.info('Soft-deleting record', { recordId, userId });
      }

      // Update the record in the database
      const updatedRecord = await recordRelationService.updateRecord(
        recordId,
        updatedData,
        keyValueStoreService,
      );

      // Log the successful update
      logger.info('Record updated successfully', {
        recordId,
        userId,
        orgId,
        fileUploaded,
        newFileName: fileUploaded ? fileName : undefined,
        updatedFields: Object.keys(updatedData),
        requestId: req.context?.requestId,
      });

      // Return the updated record
      res.status(200).json({
        message: fileUploaded
          ? 'Record updated with new file version'
          : 'Record updated successfully',
        record: updatedRecord,
        meta: {
          requestId: req.context?.requestId,
          timestamp: new Date().toISOString(),
        },
      });
    } catch (error: any) {
      // Log the error for debugging
      logger.error('Error updating record', {
        recordId: req.params.recordId,
        error: error.message,
        stack: error.stack,
        userId: req.user?.userId,
        orgId: req.user?.orgId,
        requestId: req.context?.requestId,
      });

      next(error);
    }
  };
/**
 * Delete (soft-delete) a record
 */
export const deleteRecord =
  (recordRelationService: RecordRelationService) =>
  async (
    req: AuthenticatedUserRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      const { recordId } = req.params as { recordId: string };
      const { userId, orgId } = req.user || {};

      if (!userId || !orgId) {
        throw new UnauthorizedError('User authentication is required');
      }

      // Check if user has permission to delete records
      try {
        await recordRelationService.validateUserKbAccess(userId, orgId, [
          'OWNER','WRITER','FILEORGANIZER'
        ]);
      } catch (error) {
        throw new ForbiddenError('Permission denied');
      }

      // Get the current record to confirm it exists
      let existingRecord;
      try {
        existingRecord = await recordRelationService.getRecordById(
          recordId,
          userId,
          orgId,
        );
        if (!existingRecord || !existingRecord.record) {
          throw new NotFoundError(`Record with ID ${recordId} not found`);
        }
      } catch (error) {
        throw new NotFoundError(`Record with ID ${recordId} not found`);
      }
      // const time = Date.now();
      // Perform soft delete
      // const softDeleteData = {
      //   isDeleted: true,
      //   deletedByUserId: userId,
      //   // deletedAtTimestamp: time,
      //   updatedAtTimestamp: time,
      //   isLatestVersion: true,
      // };

      // Update the record for soft delete
      // await recordRelationService.updateRecord(recordId, softDeleteData);
      await recordRelationService.softDeleteRecord(recordId, userId);
      // Log the successful deletion
      logger.info('Record soft-deleted successfully', {
        recordId,
        userId,
        orgId,
        requestId: req.context?.requestId,
      });

      // Return success response
      res.status(200).json({
        message: 'Record deleted successfully',
        meta: {
          requestId: req.context?.requestId,
          timestamp: new Date().toISOString(),
        },
      });
    } catch (error: any) {
      // Log the error for debugging
      logger.error('Error deleting record', {
        recordId: req.params.recordId,
        error: error.message,
        stack: error.stack,
        userId: req.user?.userId,
        orgId: req.user?.orgId,
        requestId: req.context?.requestId,
      });

      next(error);
    }
  };

export const getRecords =
  (recordRelationService: RecordRelationService) =>
  async (
    req: AuthenticatedUserRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      // Extract user from request
      const userId = req.user?.userId;
      const orgId = req.user?.orgId;

      // Validate user authentication
      if (!userId || !orgId) {
        throw new NotFoundError(
          'User not authenticated or missing organization ID',
        );
      }

      // Extract and parse query parameters
      const page = req.query.page ? parseInt(String(req.query.page), 10) : 1;
      const limit = req.query.limit
        ? parseInt(String(req.query.limit), 10)
        : 20;
      const search = req.query.search ? String(req.query.search) : undefined;
      const recordTypes = req.query.recordTypes
        ? String(req.query.recordTypes).split(',')
        : undefined;
      const origins = req.query.origins
        ? String(req.query.origins).split(',')
        : undefined;
      const indexingStatus = req.query.indexingStatus
        ? String(req.query.indexingStatus).split(',')
        : undefined;

      // Parse date filters
      const dateFrom = req.query.dateFrom
        ? parseInt(String(req.query.dateFrom), 10)
        : undefined;
      const dateTo = req.query.dateTo
        ? parseInt(String(req.query.dateTo), 10)
        : undefined;

      // Sorting parameters
      const sortBy = req.query.sortBy ? String(req.query.sortBy) : undefined;
      const sortOrderParam = req.query.sortOrder
        ? String(req.query.sortOrder)
        : undefined;
      const sortOrder =
        sortOrderParam === 'asc' || sortOrderParam === 'desc'
          ? sortOrderParam
          : undefined;

      // Retrieve records using the service
      const result = await recordRelationService.getRecords({
        orgId,
        userId,
        page,
        limit,
        search,
        recordTypes,
        origins,
        indexingStatus,
        dateFrom,
        dateTo,
        sortBy,
        sortOrder,
      });

      // Log successful retrieval
      logger.info('Records retrieved successfully', {
        totalRecords: result.pagination.totalCount,
        page: result.pagination.page,
        requestId: req.context?.requestId,
      });

      // Send response
      res.status(200).json({
        ...result,
        meta: {
          requestId: req.context?.requestId,
          timestamp: new Date().toISOString(),
        },
      });
    } catch (error) {
      // Handle permission errors
      if (
        error instanceof Error &&
        (error.message.includes('does not have permission') ||
          error.message.includes('does not have the required permissions'))
      ) {
        throw new UnauthorizedError(
          'You do not have permission to access these records',
        );
      }

      // Log and forward any other errors
      logger.error('Error getting records', {
        error: error instanceof Error ? error.message : 'Unknown error',
        stack: error instanceof Error ? error.stack : undefined,
        requestId: req.context?.requestId,
      });
      next(error);
    }
  };

/**
 * Archive a record
 */
export const archiveRecord =
  (
    recordRelationService: RecordRelationService,
    keyValueStoreService: KeyValueStoreService,
  ) =>
  async (
    req: AuthenticatedUserRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      const { recordId } = req.params as { recordId: string };
      const { userId, orgId } = req.user || {};

      if (!userId || !orgId) {
        throw new UnauthorizedError('User authentication is required');
      }

      // Check if user has permission to archive records
      try {
        await recordRelationService.validateUserKbAccess(userId, orgId, [
          'OWNER','WRITER','FILEORGANIZER'
        ]);
      } catch (error) {
        throw new ForbiddenError('Permission denied');
      }

      // Get the current record to confirm it exists
      let existingRecord;
      try {
        existingRecord = await recordRelationService.getRecordById(
          recordId,
          userId,
          orgId,
        );
        if (!existingRecord || !existingRecord.record) {
          throw new NotFoundError(`Record with ID ${recordId} not found`);
        }
      } catch (error) {
        throw new NotFoundError(`Record with ID ${recordId} not found`);
      }

      // Check if record is already archived
      if (existingRecord.record.isArchived) {
        throw new ForbiddenError(
          `Record with ID ${recordId} is already archived`,
        );
      }

      // Prepare update data for archiving
      const archiveData = {
        isArchived: true,
        archivedBy: userId,
        archivedAtTimestamp: Date.now(),
        updatedAtTimestamp: Date.now(),
        isFileRecordUpdate: existingRecord.record.fileRecord ? true : false,
      };

      // Update the record in the database
      const archivedRecord = await recordRelationService.updateRecord(
        recordId,
        archiveData,
        keyValueStoreService,
      );

      // Log the successful archive
      logger.info('Record archived successfully', {
        recordId,
        userId,
        orgId,
        requestId: req.context?.requestId,
      });

      // Return the archived record
      res.status(200).json({
        message: 'Record archived successfully',
        record: {
          id: archivedRecord._key,
          name: archivedRecord.recordName,
          isArchived: archivedRecord.isArchived,
          archivedAt: new Date(archivedRecord.archivedAtTimestamp),
          archivedBy: archivedRecord.archivedBy,
        },
        meta: {
          requestId: req.context?.requestId,
          timestamp: new Date().toISOString(),
        },
      });
    } catch (error: any) {
      // Log the error for debugging
      logger.error('Error archiving record', {
        recordId: req.params.recordId,
        error: error.message,
        stack: error.stack,
        userId: req.user?.userId,
        orgId: req.user?.orgId,
        requestId: req.context?.requestId,
      });

      next(error);
    }
  };

/**
 * Unarchive a record
 */
export const unarchiveRecord =
  (
    recordRelationService: RecordRelationService,
    keyValueStoreService: KeyValueStoreService,
  ) =>
  async (
    req: AuthenticatedUserRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> => {
    try {
      const { recordId } = req.params as { recordId: string };
      const { userId, orgId } = req.user || {};

      if (!userId || !orgId) {
        throw new UnauthorizedError('User authentication is required');
      }

      // Check if user has permission to unarchive records
      try {
        await recordRelationService.validateUserKbAccess(userId, orgId, [
          'OWNER','WRITER','FILEORGANIZER'
        ]);
      } catch (error) {
        res.status(403).json({
          message: error instanceof Error ? error.message : 'Permission denied',
          error: 'FORBIDDEN',
        });
        return;
      }

      // Get the current record to confirm it exists
      let existingRecord;
      try {
        existingRecord = await recordRelationService.getRecordById(
          recordId,
          userId,
          orgId,
        );
        if (!existingRecord || !existingRecord.record) {
          throw new NotFoundError(`Record with ID ${recordId} not found`);
        }
      } catch (error) {
        throw new NotFoundError(`Record with ID ${recordId} not found`);
      }

      // Check if record is already unarchived
      if (!existingRecord.record.isArchived) {
        throw new ForbiddenError(`Record with ID ${recordId} is not archived`);
      }

      // Prepare update data for unarchiving
      const unarchiveData = {
        isArchived: false,
        // We keep the archivedBy and archivedAtTimestamp for historical purposes
        // But we add the unarchive information
        unarchivedBy: userId,
        unarchivedAtTimestamp: Date.now(),
        updatedAtTimestamp: Date.now(),
        isFileRecordUpdate: existingRecord.record.fileRecord ? true : false,
      };

      // Update the record in the database
      const unarchivedRecord = await recordRelationService.updateRecord(
        recordId,
        unarchiveData,
        keyValueStoreService,
      );

      // Log the successful unarchive
      logger.info('Record unarchived successfully', {
        recordId,
        userId,
        orgId,
        requestId: req.context?.requestId,
      });

      // Return the unarchived record
      res.status(200).json({
        message: 'Record unarchived successfully',
        record: {
          id: unarchivedRecord._key,
          name: unarchivedRecord.recordName,
          isArchived: unarchivedRecord.isArchived,
          unarchivedAt: new Date(unarchivedRecord.unarchivedAtTimestamp),
          unarchivedBy: unarchivedRecord.unarchivedBy,
        },
        meta: {
          requestId: req.context?.requestId,
          timestamp: new Date().toISOString(),
        },
      });
    } catch (error: any) {
      // Log the error for debugging
      logger.error('Error unarchiving record', {
        recordId: req.params.recordId,
        error: error.message,
        stack: error.stack,
        userId: req.user?.userId,
        orgId: req.user?.orgId,
        requestId: req.context?.requestId,
      });

      next(error);
    }
  };

// export const restoreRecord =
//   (arangoService: ArangoService) =>
//   async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
//     try {
//     } catch (error: any) {
//       logger.error('Error restoring record', error);
//       next(error);
//     }
//   };

// export const setRecordExpirationTime =
//   (arangoService: ArangoService) =>
//   async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
//     try {
//     } catch (error: any) {
//       logger.error('Error setting record expiration time', error);
//       next(error);
//     }
//   };

// export const getOCRData =
//   (arangoService: ArangoService) =>
//   async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
//     try {
//     } catch (error: any) {
//       logger.error('Error getting OCR data', error);
//       next(error);
//     }
//   };

// export const uploadNextVersion =
//   (arangoService: ArangoService) =>
//   async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
//     try {
//     } catch (error: any) {
//       logger.error('Error uploading next version', error);
//       next(error);
//     }
//   };

// export const searchInKB =
//   (arangoService: ArangoService) =>
//   async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
//     try {
//     } catch (error: any) {
//       logger.error('Error searching in KB', error);
//       next(error);
//     }
//   };

// export const answerQueryFromKB =
//   (arangoService: ArangoService) =>
//   async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
//     try {
//     } catch (error: any) {
//       logger.error('Error answering query from KB', error);
//       next(error);
//     }
//   };
