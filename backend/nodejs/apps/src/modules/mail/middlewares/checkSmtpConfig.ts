import { NextFunction, Response } from 'express';
import {
  BadRequestError,
  NotFoundError,
} from '../../../libs/errors/http.errors';

import { ContainerRequest } from '../../auth/middlewares/types';
import { MailSenderService } from '../services/mail.sender.service';

export const smtpConfigChecker = async (
  req: ContainerRequest,
  _res: Response,
  next: NextFunction,
): Promise<void> => {
  try {
    const container = req.container;
    if (!container) {
      throw new NotFoundError('Mail container not found');
    }
    // Not AppConfig: this replica may have missed the reload after email was turned on.
    const smtp = await container
      .get<MailSenderService>(MailSenderService)
      .getSmtpConfig();

    if (!smtp || !smtp.port || !smtp.host || !smtp.fromEmail) {
      throw new BadRequestError('Smtp not configured properly');
    }
    next();
  } catch (error) {
    next(error);
  }
};
