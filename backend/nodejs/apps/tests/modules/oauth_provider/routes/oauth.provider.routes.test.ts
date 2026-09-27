import 'reflect-metadata'
import express from 'express'
import type { Server } from 'http'
import { expect } from 'chai'
import sinon from 'sinon'
import { createOAuthProviderRouter } from '../../../../src/modules/oauth_provider/routes/oauth.provider.routes'

function buildContainer(overrides: Record<string, any> = {}) {
  return {
    get: sinon.stub().callsFake((key: string) => {
      if (key in overrides) return overrides[key]
      if (key === 'Logger') return { info: sinon.stub(), debug: sinon.stub(), warn: sinon.stub(), error: sinon.stub() }
      if (key === 'AuthTokenService') return { verifyToken: sinon.stub() }
      if (key === 'AppConfig') return { frontendUrl: 'http://localhost:3000', maxOAuthClientRequestsPerMinute: 1000 }
      if (key === 'OAuthProviderController') return {}
      if (key === 'OIDCProviderController') return {}
      // Named so the bound layer shows up as 'bound authenticate' in router.stack.
      if (key === 'AuthMiddleware') return { authenticate: function authenticate() {} }
      if (key === 'OAuthAuthMiddleware') return { authenticate: sinon.stub(), requireScopes: sinon.stub().returns(sinon.stub()) }
      return {}
    }),
  }
}

describe('OAuth Provider Routes', () => {
  afterEach(() => { sinon.restore() })

  describe('createOAuthProviderRouter', () => {
    it('should be a function', () => {
      expect(createOAuthProviderRouter).to.be.a('function')
    })

    it('should create a router when given a valid container', () => {
      const router = createOAuthProviderRouter(buildContainer() as any)
      expect(router).to.exist
      expect(router.stack).to.be.an('array')
      const routes = (router as any).stack
        .filter((layer: any) => layer.route)
        .map((layer: any) => {
          const method = Object.keys(layer.route.methods).find(
            (m: string) => layer.route.methods[m],
          )
          return `${method}:${layer.route.path}`
        })
      expect(routes).to.include('post:/device_authorization')
      expect(routes).to.include('post:/device/verify')
      expect(routes).to.include('post:/device/consent')
      expect(routes).to.include('post:/register')
      expect(routes).to.include('post:/token')
    })

    it('should guard POST /authorize with requireSessionAuth right after authenticate', () => {
      const router = createOAuthProviderRouter(buildContainer() as any)
      const consent = router.stack.find(
        (layer: any) => layer.route?.path === '/authorize' && layer.route.methods.post,
      )
      expect(consent).to.exist
      const names = consent!.route.stack.map((s: any) => s.name)
      const authIdx = names.indexOf('bound authenticate')
      expect(authIdx).to.be.greaterThan(-1)
      expect(names[authIdx + 1]).to.equal('requireSessionAuth')
    })

    it('should not put requireSessionAuth on the client-authenticated token endpoints', () => {
      const router = createOAuthProviderRouter(buildContainer() as any)
      for (const path of ['/token', '/revoke', '/introspect']) {
        const layer = router.stack.find((l: any) => l.route?.path === path)
        expect(layer, path).to.exist
        const names = layer!.route.stack.map((s: any) => s.name)
        expect(names, path).to.not.include('requireSessionAuth')
      }
    })
  })

  // Exercises the real middleware chain over HTTP for the consent POST: only
  // the authenticate step (decides what req.user looks like) and the
  // controller (records whether the request got through) are stubbed.
  describe('POST /authorize token-type enforcement (GHSA-5f37-vxfm-885c)', () => {
    let app: express.Express
    let server: Server | undefined
    let principal: Record<string, any> | undefined
    let controller: { authorizeConsent: sinon.SinonStub; token: sinon.SinonStub }

    beforeEach(() => {
      principal = undefined
      controller = {
        authorizeConsent: sinon.stub().callsFake((_req: any, res: any) =>
          res.status(200).json({ redirectUrl: 'https://client.example/cb?code=issued' }),
        ),
        token: sinon.stub().callsFake((_req: any, res: any) =>
          res.status(200).json({ access_token: 'at' }),
        ),
      }
      const container = buildContainer({
        OAuthProviderController: controller,
        AuthMiddleware: {
          authenticate: (req: any, _res: any, next: any) => {
            if (!principal) {
              return next(Object.assign(new Error('No token provided'), { statusCode: 401 }))
            }
            req.user = principal
            next()
          },
        },
      })
      app = express()
      app.use(express.json())
      app.use('/api/v1/oauth2', createOAuthProviderRouter(container as any))
      app.use((err: any, _req: any, res: any, _next: any) => {
        res.status(err.statusCode || 500).json({ message: err.message })
      })
    })

    afterEach(async () => {
      if (server) {
        await new Promise<void>((resolve, reject) => {
          server!.close((err) => (err ? reject(err) : resolve()))
        })
        server = undefined
      }
    })

    async function listen(): Promise<number> {
      return new Promise((resolve, reject) => {
        server = app.listen(0, () => {
          const addr = server!.address()
          if (addr && typeof addr === 'object') resolve(addr.port)
          else reject(new Error('no port'))
        })
      })
    }

    const consentBody = {
      client_id: 'attacker-client',
      redirect_uri: 'https://client.example/cb',
      scope: 'org:admin',
      state: 'st',
      consent: 'granted',
    }

    it('lets a session-authenticated user submit consent', async () => {
      principal = { userId: 'u1', orgId: 'o1', role: 'member' }
      const port = await listen()

      const res = await fetch(`http://127.0.0.1:${port}/api/v1/oauth2/authorize`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(consentBody),
      })
      expect(res.status).to.equal(200)
      expect(controller.authorizeConsent.calledOnce).to.be.true
    })

    it('rejects consent driven by an OAuth access token with 403, never reaching the controller', async () => {
      principal = {
        userId: 'u1', orgId: 'o1', role: 'member',
        isOAuth: true, oauthClientId: 'attacker-client', oauthScopes: ['org:read'],
      }
      const port = await listen()

      const res = await fetch(`http://127.0.0.1:${port}/api/v1/oauth2/authorize`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(consentBody),
      })
      expect(res.status).to.equal(403)
      expect(controller.authorizeConsent.called).to.be.false
    })

    it('rejects consent driven by a personal access token with 403', async () => {
      principal = {
        userId: 'u1', orgId: 'o1', role: 'admin',
        isOAuth: true, oauthClientId: 'pat-system:o1', oauthScopes: ['org:read'],
      }
      const port = await listen()

      const res = await fetch(`http://127.0.0.1:${port}/api/v1/oauth2/authorize`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(consentBody),
      })
      expect(res.status).to.equal(403)
      expect(controller.authorizeConsent.called).to.be.false
    })

    it('leaves POST /token (client-authenticated, no user session) unaffected', async () => {
      const port = await listen()

      const res = await fetch(`http://127.0.0.1:${port}/api/v1/oauth2/token`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ grant_type: 'client_credentials', client_id: 'c1', client_secret: 's' }),
      })
      expect(res.status).to.equal(200)
      expect(controller.token.calledOnce).to.be.true
    })
  })
})
