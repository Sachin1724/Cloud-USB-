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

const allowedOrigins = [
    'https://cloud-usb.vercel.app',
    'http://localhost:5173',
    'http://localhost:3000',
    ...(process.env.ALLOWED_ORIGINS || '').split(',').map(o => o.trim()).filter(Boolean)
];

app.use(cors({
    origin: function (origin, callback) {
        // Allow requests with no origin (like mobile apps or curl)
        if (!origin) return callback(null, true);
        
        if (allowedOrigins.indexOf(origin) !== -1 || allowedOrigins.length === 0) {
            callback(null, true);
        } else {
            console.log('[CORS] Blocked origin:', origin);
            callback(new Error('Not allowed by CORS'));
        }
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-agent-id', 'x-active-drive']
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
