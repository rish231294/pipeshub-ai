import express, { Router } from 'express';
import { Container } from 'inversify';
import { SocketIOService } from '../service/socketio.service';
import { InternalServerError, NotFoundError } from '../../../libs/errors/http.errors';
import { Logger } from '../../../libs/services/logger.service';

const logger = Logger.getInstance({service: 'SocketIO'}); 

export const createSocketIORouter = (container: Container): Router => {
  const router = express.Router();
  const socketIOService = container.get<SocketIOService>(SocketIOService);


  // Send notification to a specific user
  router.post('/notify/user/:userId', (req, res) => {
    try {
      logger.debug('Sending notification to user', {
        userId: req.params.userId,
        event: req.body.event,
        data: req.body.data,
      });
      const { userId } = req.params;
      const { event = 'notification', data } = req.body;
      
      const success = socketIOService.sendToUser(userId, event, data);
      
      if (success) {
        res.status(200).json({ 
          status: 'success', 
          message: `Notification sent to user ${userId}` 
        });
      } else {
        throw new NotFoundError('User not connected or service unavailable');
      }
    } catch (error: any) {
      throw new InternalServerError('Failed to send notification', error);
    }
  });

  // Send notification to all users in an organization
  router.post('/notify/org/:orgId', (req, res) => {
    try {
      logger.debug('Sending notification to organization', {
        orgId: req.params.orgId,
        event: req.body.event,
        data: req.body.data,
      });
      const { orgId } = req.params;
      const { event = 'notification', data } = req.body;
      
      const success = socketIOService.sendToOrg(orgId, event, data);
      
      if (success) {
        res.status(200).json({ 
          status: 'success', 
          message: `Notification sent to all users in organization ${orgId}` 
        });
      } else {
        throw new NotFoundError('Service unavailable');
      }
    } catch (error: any) {
      throw new InternalServerError('Failed to send notification to organization', error);
    }
  });

  // Broadcast notification to all connected users
  router.post('/notify/broadcast', (req, res) => {
    try {
      logger.debug('Broadcasting notification to all connected users', {
        event: req.body.event,
        data: req.body.data,
      });
      const { event = 'notification', data } = req.body;
      
      socketIOService.broadcastToAll(event, data);
      
      res.status(200).json({ 
        status: 'success', 
        message: 'Notification broadcasted to all connected users' 
      });
    } catch (error: any) {
      throw new InternalServerError('Failed to broadcast notification', error);
    }
  });


  return router;
}