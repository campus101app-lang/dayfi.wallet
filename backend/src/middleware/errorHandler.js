// src/middleware/auth.js
import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

export async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization token required' });
  }

  const token = authHeader.split(' ')[1];

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // Don't allow setup tokens for regular routes
    if (decoded.setupMode) {
      return res.status(401).json({ error: 'Setup token cannot be used here' });
    }

    const user = await prisma.user.findUnique({
      where: { id: decoded.userId },
      select: {
        id: true,
        email: true,
        username: true,
        stellarPublicKey: true,
        isVerified: true,
      }
    });

    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    req.user = user;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

// src/middleware/errorHandler.js
export function errorHandler(err, req, res, next) {
  console.error('Unhandled error:', err);

  if (err.code === 'P2002') {
    return res.status(409).json({ error: 'Record already exists' });
  }

  res.status(err.status || 500).json({
    error: process.env.NODE_ENV === 'production'
      ? 'Internal server error'
      : err.message,
  });
}
