import { WebSocketServer } from 'ws';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';

class TunnelBroker {
    constructor() {
        this.agents = new Map();       // agentId → WebSocket (live connections)
        this.pendingRequests = new Map(); // requestId → pending HTTP response
        // Persists drive info per user — email is the primary key
        // agentInfo stores: { email, drives: [{drive, online, lastSeen}], lastSeen }
        this.agentInfo = new Map();
        this.sharedLinks = new Map(); // token -> { email, path, drive, views, createdAt }
    }

    // Get agent info with all drives
    getAgentInfo(email) {
        return this.agentInfo.get(email) || null;
    }

    // Add or update a drive for an agent (email is the key)
    registerDrive(email, rawDrive) {
        if (!email) return;
        const drive = rawDrive.replace(/[\\/]+$/, '').trim();
        const info = this.agentInfo.get(email) || { email, agentId: null, online: false, drives: [] };
        if (!info.drives) info.drives = [];
        const driveUpper = drive.toUpperCase();
        const existingIndex = info.drives.findIndex(d => d.drive.toUpperCase() === driveUpper);
        
        if (existingIndex >= 0) {
            info.drives[existingIndex].online = true; // assume online if registering
            info.drives[existingIndex].lastSeen = new Date().toISOString();
        } else {
            info.drives.push({
                drive,
                online: true,
                lastSeen: new Date().toISOString()
            });
        }
        
        // Set this drive as the active (selected) drive
        info.activeDrive = drive;
        info.lastSeen = new Date().toISOString();
        this.agentInfo.set(email, info);
        return info;
    }
    
    // Set the active drive (emaul is the key)
    setActiveDrive(email, rawDrive) {
        const drive = rawDrive.replace(/[\\/]+$/, '').trim();
        const info = this.agentInfo.get(email);
        if (info) {
            info.activeDrive = drive;
            this.agentInfo.set(email, info);
        }
        return info;
    }

    init(server) {
        const maxPayload = Number(process.env.WS_MAX_PAYLOAD_BYTES || (64 * 1024 * 1024));
        this.wss = new WebSocketServer({
            server,
            maxPayload: Number.isFinite(maxPayload) ? maxPayload : (64 * 1024 * 1024)
        });

        this.wss.on('connection', (ws, req) => {
            const authHeader = req.headers['authorization'];
            const token = authHeader && authHeader.split(' ')[1];

            if (!token) {
                console.error('[DriveNet] Agent connection rejected (No token)');
                ws.close(1008, 'Token missing');
                return;
            }

            let decoded;
            try {
                decoded = jwt.verify(token, process.env.JWT_SECRET);
            } catch (err) {
                console.error(`[DriveNet] Agent connection rejected (Invalid token)`);
                ws.close(1008, 'Invalid token');
                return;
            }

            // SECURITY: Enforce Agent ID to the Google UID of the logged-in user
            const agentId = decoded.g_uid || decoded.user;

            if (!agentId) {
                console.error(`[DriveNet] Agent connection rejected (No Identity in Token)`);
                ws.close(1008, 'Identity Error');
                return;
            }

            console.log(`[DriveNet] Agent Connected & Authenticated for User: ${decoded.user} (AgentID: ${agentId})`);

            this.agents.set(agentId, ws);

            // Track this agent's email and online status — email is the primary key for info
            const email = decoded.user;
            const existing = this.agentInfo.get(email) || {};
            this.agentInfo.set(email, {
                drives: [], // Initialize drives list
                ...existing,
                email: email,
                agentId,
                online: true,
                lastSeen: new Date().toISOString(),
            });

            // NEW: Auto-register active drive from headers (fixes sync after restart)
            const rawActiveDrive = req.headers['x-active-drive'];
            if (rawActiveDrive) {
                const activeDrive = rawActiveDrive.replace(/[\\/]+$/, '').trim();
                this.registerDrive(email, activeDrive);
                console.log(`[DriveNet] Auto-registered drive from connection: ${email} → ${activeDrive}`);
            }

            ws.on('message', (message) => {
                let data;
                try {
                    data = JSON.parse(message.toString());
                } catch (err) {
                    // Ignore non-JSON messages (e.g., ping frames)
                    return;
                }
                try {
                    if (data.requestId && this.pendingRequests.has(data.requestId)) {
                        const pendingReq = this.pendingRequests.get(data.requestId);

                        if (pendingReq.res) {
                            const res = pendingReq.res;
                            if (data.error) {
                                if (!res.headersSent) res.status(500).json({ error: data.error });
                                this.pendingRequests.delete(data.requestId);
                            } else if (data.payload && data.payload.type === 'start') {
                                if (data.payload.statusCode) {
                                    res.status(data.payload.statusCode);
                                }
                                if (data.payload.headers) {
                                    Object.entries(data.payload.headers).forEach(([key, value]) => {
                                        res.setHeader(key, value);
                                    });
                                } else {
                                    res.setHeader('Content-Disposition', `attachment; filename="${data.payload.filename || 'download.bin'}"`);
                                    if (data.payload.size !== undefined) {
                                        res.setHeader('Content-Length', data.payload.size);
                                    }
                                    res.setHeader('Content-Type', 'application/octet-stream');
                                }
                            } else if (data.payload && data.payload.type === 'chunk') {
                                res.write(Buffer.from(data.payload.data, 'base64'));
                            } else if (data.payload && data.payload.type === 'end') {
                                res.end();
                                this.pendingRequests.delete(data.requestId);
                            } else if (data.isFile) {
                                // Backward compatibility
                                const fileBuffer = Buffer.from(data.payload, 'base64');
                                res.setHeader('Content-Disposition', `attachment; filename="${data.filename || 'download.bin'}"`);
                                res.setHeader('Content-Type', 'application/octet-stream');
                                res.send(fileBuffer);
                                this.pendingRequests.delete(data.requestId);
                            } else {
                                res.json(data.payload);
                                this.pendingRequests.delete(data.requestId);
                            }
                        } else if (pendingReq.resolve) {
                            if (data.error) pendingReq.reject(new Error(data.error));
                            else pendingReq.resolve(data.payload);
                            this.pendingRequests.delete(data.requestId);
                        }
                    }
                } catch (err) {
                    console.error('WS MSG Handler Error:', err.message);
                }
            });

            ws.on('close', () => {
                console.log(`[DriveNet] Agent Disconnected: ${agentId}`);
                this.agents.delete(agentId);
                // Mark offline in the email-keyed info
                const email = decoded.user;
                const info = this.agentInfo.get(email);
                if (info) this.agentInfo.set(email, { ...info, online: false, lastSeen: new Date().toISOString() });
            });
        });
    }

    // Forward an HTTP request to the connected Agent via WebSocket
    async forwardRequest(agentId, action, payload = {}) {
        return new Promise((resolve, reject) => {
            const ws = this.agents.get(agentId);
            if (!ws || ws.readyState !== 1) {
                return reject(new Error('Agent is offline'));
            }

            const requestId = crypto.randomUUID();
            this.pendingRequests.set(requestId, { resolve, reject, timestamp: Date.now() });

            ws.send(JSON.stringify({
                requestId,
                action,
                payload
            }));

            // Timeout after 30 seconds
            setTimeout(() => {
                if (this.pendingRequests.has(requestId)) {
                    const req = this.pendingRequests.get(requestId);
                    req.reject(new Error('Agent response timeout'));
                    this.pendingRequests.delete(requestId);
                }
            }, 30000);
        });
    }

    registerSharedLink(token, email, path, drive) {
        this.sharedLinks.set(token, {
            email,
            path,
            drive,
            views: 0,
            createdAt: new Date().toISOString()
        });
    }

    incrementShareView(token) {
        const link = this.sharedLinks.get(token);
        if (link) {
            link.views++;
            return link;
        }
        return null;
    }

    getSharedLinks(email) {
        return Array.from(this.sharedLinks.entries())
            .filter(([_, val]) => val.email === email)
            .map(([token, val]) => ({ token, ...val }));
    }

    // Specifically for HTTP routes
    createProxyHandler(action) {
        return async (req, res) => {
            try {
                // Get the drive from query parameter
                const drive = req.query.drive || req.body?.drive;
                const token = req.query.token || req.body?.token;
                
                // SECURITY: Route exactly to the agent associated with the requesting user
                const agentId = req.user?.g_uid || req.user?.user;
                if (!agentId) return res.status(401).json({ error: 'Unidentified User Request' });
                const requestId = crypto.randomUUID();

                // Track share views if token present
                if (token && action === 'fs:download') {
                    this.incrementShareView(token);
                }

                const ws = this.agents.get(agentId);
                if (!ws || ws.readyState !== 1) {
                    return res.status(503).json({ error: 'SYSTEM OFFLINE. USB Agent disconnected.' });
                }

                this.pendingRequests.set(requestId, { res, timestamp: Date.now() });

                ws.send(JSON.stringify({
                    requestId,
                    action,
                    payload: { ...req.body, ...req.query, ...req.params, drive }
                }));

                // Timeout after 30 seconds
                setTimeout(() => {
                    if (this.pendingRequests.has(requestId)) {
                        const pendingReq = this.pendingRequests.get(requestId);
                        if (!pendingReq.res.headersSent) {
                            pendingReq.res.status(504).json({ error: 'Agent response timeout' });
                        }
                        this.pendingRequests.delete(requestId);
                    }
                }, 30000);
            } catch (err) {
                console.error('Proxy Handler Error:', err);
                if (!res.headersSent) {
                    res.status(500).json({ error: 'Internal Server Error forwarding request.' });
                }
            }
        };
    }
}

export const tunnelBroker = new TunnelBroker();
