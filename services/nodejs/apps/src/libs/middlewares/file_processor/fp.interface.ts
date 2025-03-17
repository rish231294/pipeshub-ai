import { FileProcessingType } from "./fp.constant";
import { Request, Response, NextFunction, RequestHandler } from "express";

export interface FileProcessorConfiguration {
    fieldName: string;
    maxFileSize: number;
    allowedMimeTypes: string[];
    maxFilesAllowed: number;
    isMultipleFilesAllowed: boolean;
    processingType: FileProcessingType;
    strictFileUpload: boolean;
}

export interface FileBufferInfo {
    buffer: Buffer;
    originalname: string;
    mimetype: string;
    size: number;
}

export interface IFileUploadService {
    upload(): RequestHandler;
    processFiles(): RequestHandler;
    getMiddleware(): Array<RequestHandler>;
}