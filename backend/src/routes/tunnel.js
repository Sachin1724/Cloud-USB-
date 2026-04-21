import express from 'express';
import jwt from 'jsonwebtoken';
import { authenticateToken } from './auth.js';
import { tunnelBroker } from '../tunnel/broker.js';

const router = express.Router();

// Secure all file system routes
router.use(authenticateToken);

// ─── DRIVE IDENTITY ROUTES ────────────────────────────────────────────────────

router.get('/me/agent', (req, res) => {
    const email = req.user?.user;
    if (!email) return res.status(401).json({ error: 'Unidentified User' });

    const info = tunnelBroker.getAgentInfo(email);
    if (!info) {
        return res.json({ online: false, drive: null, drives: [], email: req.user?.user });
    }

    const liveOnline = tunnelBroker.agents.has(agentId);
    const drivesWithOnlineStatus = (info.drives || []).map(d => ({
        ...d,
        online: liveOnline
    }));

    return res.json({
        online: liveOnline,
        drive: info.activeDrive || (drivesWithOnlineStatus.length > 0 ? drivesWithOnlineStatus[0].drive : null),
        drives: drivesWithOnlineStatus,
        email: req.user?.user
    });
});

router.post('/me/set-active-drive', express.json(), (req, res) => {
    const email = req.user?.user;
    if (!email) return res.status(401).json({ error: 'Unidentified User' });
    const { drive } = req.body;
    if (!drive) return res.status(400).json({ error: 'drive field required' });

    tunnelBroker.setActiveDrive(email, drive);
    console.log(`[DriveNet] Active drive set: ${email} → ${drive}`);
    return res.json({ ok: true, drive });
});

router.post('/me/register-drive', express.json(), (req, res) => {
    const email = req.user?.user;
    if (!email) return res.status(401).json({ error: 'Unidentified User' });
    const { drive } = req.body;
    if (!drive) return res.status(400).json({ error: 'drive field required' });

    const info = tunnelBroker.registerDrive(email, drive);
    console.log(`[DriveNet] Drive registered: ${email} → ${drive}`);

    return res.json({
        ok: true,
        drive: info.activeDrive || drive,
        drives: info.drives,
        online: tunnelBroker.agents.has(agentId)
    });
});

// ─── FILE SYSTEM PROXY ROUTES ─────────────────────────────────────────────────

router.get('/list', tunnelBroker.createProxyHandler('fs:list'));
router.post('/folder', tunnelBroker.createProxyHandler('fs:mkdir'));
router.delete('/delete', tunnelBroker.createProxyHandler('fs:delete'));
router.post('/rename', tunnelBroker.createProxyHandler('fs:rename'));
router.get('/stats', tunnelBroker.createProxyHandler('sys:stats'));

router.get('/download', tunnelBroker.createProxyHandler('fs:download'));
router.get('/video', tunnelBroker.createProxyHandler('fs:stream'));
router.get('/thumbnail', tunnelBroker.createProxyHandler('fs:thumbnail'));

// ─── NEW: SEARCH, TRASH, RESTORE ─────────────────────────────────────────────

// GET /api/fs/search?q=filename&path=...&drive=...
router.get('/search', tunnelBroker.createProxyHandler('fs:search'));

// DELETE /api/fs/trash?path=...&drive=...  → soft-delete (move to .drivenet_trash)
router.delete('/trash', tunnelBroker.createProxyHandler('fs:trash'));

// GET /api/fs/trash/list?drive=...
router.get('/trash/list', tunnelBroker.createProxyHandler('fs:trash_list'));

// POST /api/fs/restore  body: { path, drive }
router.post('/restore', express.json(), tunnelBroker.createProxyHandler('fs:restore'));

// DELETE /api/fs/trash/purge  body: { path?, drive }  — permanently delete from trash
router.delete('/trash/purge', tunnelBroker.createProxyHandler('fs:trash_purge'));

// ─── CHUNKED UPLOAD ───────────────────────────────────────────────────────────

router.post('/upload_chunk', express.json({ limit: '10mb' }), tunnelBroker.createProxyHandler('fs:upload_chunk'));

// ─── SHARE LINK ───────────────────────────────────────────────────────────────

router.get('/share', (req, res) => {
    const jwtSecret = process.env.JWT_SECRET || '';
    if (!jwtSecret) return res.status(500).json({ error: 'Server auth misconfigured: JWT secret missing' });

    const path = typeof req.query.path === 'string' ? req.query.path : '';
    const drive = typeof req.query.drive === 'string' ? req.query.drive : '';
    if (!path) return res.status(400).json({ error: 'path query required' });

    const token = jwt.sign({
        user: req.user?.user,
        g_uid: req.user?.g_uid || req.user?.user,
        scope: 'share',
        path,
        drive
    }, jwtSecret, { expiresIn: '15m' });

    const baseUrl = process.env.PUBLIC_API_URL ||
        `${req.protocol}://${req.get('host')}`;

    const url = `${baseUrl.replace(/\/$/, '')}/api/fs/download?path=${encodeURIComponent(path)}&drive=${encodeURIComponent(drive)}&token=${encodeURIComponent(token)}`;
    return res.json({ url, expiresIn: '15m', path, drive });
});

// ─── REGULAR UPLOAD ───────────────────────────────────────────────────────────

router.post('/upload', express.json({ limit: '25mb' }), async (req, res) => {
    try {
        const { path: folderPath, name, content, drive } = req.body;
        const agentId = req.user?.g_uid || req.user?.user;
        if (!agentId) return res.status(401).json({ error: 'Unidentified User Request' });
        const result = await tunnelBroker.forwardRequest(agentId, 'fs:upload', { path: folderPath, name, content, drive });
        res.json(result);
    } catch (err) {
        res.status(500).json({ error: err.message || 'Tunnel Communication Error' });
    }
});

// ─── JWT REFRESH ──────────────────────────────────────────────────────────────

router.post('/auth/refresh', (req, res) => {
    const jwtSecret = process.env.JWT_SECRET || '';
    if (!jwtSecret) return res.status(500).json({ error: 'Server auth misconfigured' });
    // req.user is already verified by authenticateToken middleware above
    const newToken = jwt.sign(
        { user: req.user.user, g_uid: req.user.g_uid },
        jwtSecret,
        { expiresIn: '24h' }
    );
    return res.json({ token: newToken });
});

export default router;
