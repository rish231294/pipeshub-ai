import passport from 'passport';
import {
  Strategy as SamlStrategy,
  Profile,
  VerifiedCallback,
  VerifyWithRequest,
} from 'passport-saml';
import { Response, NextFunction } from 'express';
import { AuthSessionRequest } from '../middlewares/types';
import { IamService } from '../services/iam.service';
import { OrgAuthConfig } from '../schema/orgAuthConfiguration.schema';
import { Logger } from '../../../libs/services/logger.service';
import {
  BadRequestError,
  InternalServerError,
  NotFoundError,
} from '../../../libs/errors/http.errors';
import { inject, injectable } from 'inversify';
import {
  ConfigurationManagerCommandOptions,
  ConfigurationManagerServiceCommand,
} from '../../../libs/commands/configuration_manager/cm.service.command';
import { HttpMethod } from '../../../libs/enums/http-methods.enum';
import { generateAuthToken } from '../utils/generateAuthToken';
import { iamJwtGenerator } from '../../../libs/utils/createJwt';
import { AuthConfig } from '../config/config';
const orgIdToSamlEmailKey: Record<string, string> = {};
passport.serializeUser((user, done) => {
  done(null, user);
});

passport.deserializeUser((obj, done) => {
  if (obj) {
    done(null, obj);
  }
});
@injectable()
export class SamlController {
  constructor(
    @inject('IamService') private iamService: IamService,
    @inject('AuthConfig') private config: AuthConfig,
    @inject('Logger') private logger: Logger,
  ) {}
  // update the mapping
  updateOrgIdToSamlEmailKey(orgId: string, samlEmailKey: string) {
    orgIdToSamlEmailKey[orgId] = samlEmailKey;
  }

  // get the samlEmailKey by orgId
  getSamlEmailKeyByOrgId(orgId: string) {
    const entry = orgIdToSamlEmailKey[orgId];
    return entry ? entry : 'email';
  }

  b64DecodeUnicode(str: string) {
    return decodeURIComponent(
      atob(str)
        .split('')
        .map(function (c) {
          return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
        })
        .join(''),
    );
  }
  updateSAMLStrategy(samlCertificate: string, samlEntryPoint: string) {
    passport.use(
      new SamlStrategy(
        {
          entryPoint: samlEntryPoint, // Don't modify the entry point directly
          callbackUrl: `http://localhost:3000/api/v1/samlSignIn/signIn/callback`,
          cert: samlCertificate,
          passReqToCallback: true, // Allows req access in callback
        },
        function (
          req: AuthSessionRequest,
          profile: Profile,
          done: VerifiedCallback,
        ) {
          // Retrieve RelayState (which contains email & sessionToken)
          const relayStateBase64 = req.body.RelayState || req.query.RelayState;
          const relayStateDecoded = relayStateBase64
            ? JSON.parse(
                Buffer.from(relayStateBase64, 'base64').toString('utf8'),
              )
            : {};
          // Attach email & sessionToken to the user profile
          profile.orgId = relayStateDecoded.orgId;
          profile.sessionToken = relayStateDecoded.sessionToken;

          done(null, profile);
        } as VerifyWithRequest,
      ),
    );
  }

  async signInViaSAML(
    req: AuthSessionRequest,
    res: Response,
    next: NextFunction,
  ): Promise<void> {
    try {
      const email = req.query.email as string;
      const sessionToken = req.query.sessionToken as string;

      if (!email) {
        throw new BadRequestError('Email is required');
      }
      this.logger.debug(email);
      const authToken = iamJwtGenerator(email, this.config.scopedJwtSecret);
      let result = await this.iamService.getUserByEmail(email, authToken);
      if (result.statusCode !== 200) {
        throw new NotFoundError('User not found');
      }
      const user = result.data;
      const orgId = user.orgId;
      const orgAuthConfig = await OrgAuthConfig.findOne({
        orgId: user.orgId,
        // domain,
        isDeleted: false,
      });

      if (!orgAuthConfig) {
        throw new NotFoundError('Organisation configuration not found');
      }
      let configurationManagerCommandOptions: ConfigurationManagerCommandOptions =
        {
          uri: `http://localhost:3000/api/v1/configurationManager/internal/authConfig/sso`,
          method: HttpMethod.GET,
          headers: {
            Authorization: `Bearer ${await generateAuthToken(user, this.config.scopedJwtSecret)}`,
            'Content-Type': 'application/json',
          },
        };
      const getCredentialsCommand = new ConfigurationManagerServiceCommand(
        configurationManagerCommandOptions,
      );
      let response = await getCredentialsCommand.execute();

      if (response.statusCode !== 200) {
        throw new InternalServerError(
          'Error getting saml credentials',
          response?.data,
        );
      }
      const credentialsData = response.data;
      if (!credentialsData.certificate) {
        throw new NotFoundError('Certificate is missing');
      }
      if (!credentialsData.entryPoint) {
        throw new NotFoundError('entryPoint is missing');
      }
      if (!credentialsData.emailKey) {
        throw new NotFoundError('email key is missing');
      }

      const samlCertificate = credentialsData.certificate;
      const samlEntryPoint = credentialsData.entryPoint;
      const samlEmailKey = credentialsData.emailKey;

      this.updateOrgIdToSamlEmailKey(user.orgId, samlEmailKey!);
      this.updateSAMLStrategy(samlCertificate!, samlEntryPoint!);

      const relayStateObj = { orgId, sessionToken };
      const relayStateEncoded = Buffer.from(
        JSON.stringify(relayStateObj),
      ).toString('base64');
      req.query.RelayState = relayStateEncoded;
      passport.authenticate('saml', {
        failureRedirect: '/',
        successRedirect: '/', // You can modify this if needed
        // Pass RelayState using `state`
      })(req, res, next);
    } catch (error) {
      next(error);
    }
  }
}
