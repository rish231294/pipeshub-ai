import { Router, Response, NextFunction } from 'express';

import { attachContainerMiddleware } from '../../auth/middlewares/attachContainer.middleware';
import { Container } from 'inversify';
import { MailController } from '../controller/mail.controller';
import { z } from 'zod';
import { ValidationMiddleware } from '../../../libs/middlewares/validation.middleware';
import { AuthMiddleware } from '../../../libs/middlewares/auth.middleware';
import { userAdminCheck } from '../../user_management/middlewares/userAdminCheck';
import {
  AuthenticatedUserRequest,
  AuthenticatedServiceRequest,
} from '../../../libs/middlewares/types';
import { smtpConfigChecker } from '../middlewares/checkSmtpConfig';
import { TokenScopes } from '../../../libs/enums/token-scopes.enum';
import { jwtValidator } from '../middlewares/userAuthentication';
import { AppConfig, loadAppConfig } from '../../tokens_manager/config/config';

export const smtpConfigSchema = z.object({
  body: z.object({
    host: z.string().min(1, { message: 'SMTP host is required' }),
    port: z.number().min(1, { message: 'SMTP port is required' }),
    username: z.string().optional(),
    password: z.string().optional(),
    fromEmail: z.string().min(1, { message: 'SMTP from is required' }),
  }),
});
export function createMailServiceRouter(container: Container) {
  const router = Router();
  router.use(attachContainerMiddleware(container));
  const mailController = container.get<MailController>('MailController');
  const authMiddleware = container.get<AuthMiddleware>('AuthMiddleware');
  router.post(
    '/emails/sendEmail',
    smtpConfigChecker,
    jwtValidator,
    async (req: AuthenticatedUserRequest, res: Response, next: NextFunction) => {
      try {
        await mailController.sendMail(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  router.post(
    '/emails/sendUnprotectedEmail',
    smtpConfigChecker,
    authMiddleware.scopedTokenValidator(TokenScopes.SEND_MAIL),
    async (req: AuthenticatedServiceRequest, res: Response, next: NextFunction) => {
      try {
        await mailController.sendMail(req, res, next);
      } catch (error) {
        next(error);
      }
    },
  );

  router.post(
    '/updateSmtpConfig',
    ValidationMiddleware.validate(smtpConfigSchema),
    authMiddleware.authenticate,
    userAdminCheck,
    async (
      _req: AuthenticatedUserRequest,
      res: Response,
      next: NextFunction,
    ) => {
      try {
        // Reload configuration (Optional: You may choose to restart the service instead)
        const updatedConfig: AppConfig = await loadAppConfig();

        res.status(200).json({
          message: 'SMTP configuration updated successfully',
          smtp: updatedConfig.smtp,
        });
        return;
      } catch (error) {
        next(error);
      }
    },
  );
  return router;
}
