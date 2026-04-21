import dotenv from 'dotenv';
dotenv.config();

import express from 'express';
import { createServer } from 'http';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import authRoutes from './routes/auth.js';
import tunnelRoutes from './routes/tunnel.js';
import { tunnelBroker } from './tunnel/broker.js';

const app = express();
const server = createServer(app);

const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

app.use(cors({
    origin(origin, cb) {
        if (!origin) return cb(null, true);
        if (allowedOrigins.length === 0 || allowedOrigins.includes(origin)) return cb(null, true);
        return cb(new Error('CORS blocked'));
    }
}));

// Rate limiting – 120 requests per minute per IP
const limiter = rateLimit({
    windowMs: 60 * 1000,
    max: 120,
    standardHeaders: true,
    legacyHeaders: false,
    message: { error: 'Too many requests, please slow down.' },
});
app.use('/api/', limiter);

app.use(express.json({ limit: process.env.JSON_LIMIT || '10mb' }));
app.use(express.urlencoded({ limit: process.env.URLENCODED_LIMIT || '10mb', extended: true }));

// Health check
app.get('/api/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'DriveNet Cloud Broker',
        agentsOnline: tunnelBroker.agents.size,
        uptime: Math.floor(process.uptime()),
        timestamp: new Date().toISOString(),
    });
});

// Main App Routes
app.use('/api/auth', authRoutes);
app.use('/api/fs', tunnelRoutes);

// Initialize WebSocket Tunnel Broker
tunnelBroker.init(server);

const PORT = process.env.PORT || 8000;
server.listen(PORT, () => {
    console.log(`[DriveNet Cloud] Server active on port ${PORT}`);
});
