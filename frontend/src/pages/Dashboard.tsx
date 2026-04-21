import React, { useState, useEffect } from 'react';
import { useNavigate, Outlet, useLocation } from 'react-router-dom';
import axios from 'axios';

interface UserProfile {
    user: string;
    g_uid: string;
}

interface AgentStatus {
    online: boolean;
    drive: string | null;
    drives: { drive: string; online: boolean }[];
    email: string;
}

const Dashboard: React.FC = () => {
    const RAW_API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    const navigate = useNavigate();
    const location = useLocation();

    const [user, setUser] = useState<UserProfile | null>(null);
    const [agent, setAgent] = useState<AgentStatus | null>(null);
    const [loading, setLoading] = useState(true);

    const fetchData = async () => {
        const token = localStorage.getItem('drivenet_token');
        if (!token) {
            navigate('/login');
            return;
        }

        try {
            const [userRes, agentRes] = await Promise.all([
                axios.get(`${API}/api/auth/me`, { headers: { Authorization: `Bearer ${token}` } }),
                axios.get(`${API}/api/fs/me/agent`, { headers: { Authorization: `Bearer ${token}` } })
            ]);
            setUser(userRes.data);
            setAgent(agentRes.data);

            // Sync Logic: Redirect to active drive if on /dashboard root
            if (location.pathname === '/dashboard' || location.pathname === '/dashboard/') {
                const activeDrive = agentRes.data.drive;
                if (activeDrive) {
                    navigate(`/dashboard/files?drive=${encodeURIComponent(activeDrive)}`);
                }
            }
        } catch (err: any) {
            console.error('[Dashboard] Fetch error:', err);
            if (err.response?.status === 401) {
                localStorage.removeItem('drivenet_token');
                navigate('/login');
            }
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
        // Poll for agent status updates every 10 seconds
        const interval = setInterval(fetchData, 10000);
        return () => clearInterval(interval);
    }, [location.pathname]);

    const handleLogout = () => {
        localStorage.removeItem('drivenet_token');
        navigate('/login');
    };

    if (loading && !user) {
        return (
            <div className="min-h-screen bg-dn-bg flex items-center justify-center">
                <div className="w-10 h-10 border-4 border-dn-accent/20 border-t-dn-accent rounded-full animate-spin" />
            </div>
        );
    }

    return (
        <div className="flex min-h-screen bg-dn-bg overflow-hidden text-dn-text">
            {/* Sidebar (Global Stitch Shell) */}
            <aside className="fixed left-0 top-0 h-screen w-[200px] z-50 glass-sidebar flex flex-col py-8 px-4 gap-10">
                <div className="px-2">
                    <span 
                        className="text-xl font-black tracking-tighter text-dn-text cursor-pointer"
                        onClick={() => navigate('/')}
                    >
                        DriveNet Explorer
                    </span>
                    
                    {/* User Profile Section */}
                    <div className="flex items-center gap-3 mt-8 p-2 rounded-xl hover:bg-white/5 transition-colors cursor-pointer group relative">
                        <div className="w-8 h-8 rounded-full bg-dn-accent/20 flex items-center justify-center text-dn-accent font-bold text-xs uppercase shadow-sm">
                            {user?.user?.charAt(0) || 'U'}
                        </div>
                        <div className="flex flex-col overflow-hidden">
                            <span className="text-xs font-semibold truncate text-dn-text" title={user?.user}>
                                {user?.user?.split('@')[0] || 'User'}
                            </span>
                            <span className="text-[10px] text-dn-subtext uppercase tracking-wider font-bold opacity-60">Pro Account</span>
                        </div>
                        
                        {/* Tooltip or Mini-Menu placeholder */}
                        <div className="absolute left-full ml-4 px-3 py-2 bg-dn-surface-highest rounded-lg opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none whitespace-nowrap text-[10px] font-bold border border-dn-border/20 z-[60]">
                            {user?.user}
                        </div>
                    </div>
                </div>

                <nav className="flex flex-col gap-1 flex-1">
                    <button 
                        onClick={() => navigate('/dashboard/files')}
                        className={`relative flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all text-sm font-medium ${
                            location.pathname.includes('/files') 
                                ? 'text-dn-text bg-dn-accent/10 active-nav-indicator scale-[0.98]' 
                                : 'text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text'
                        }`}
                    >
                        <span className={`material-symbols-outlined ${location.pathname.includes('/files') ? 'text-dn-primary' : ''}`} style={{ fontVariationSettings: location.pathname.includes('/files') ? "'FILL' 1" : "" }}>folder</span>
                        <span>My Vault</span>
                    </button>
                    <button 
                        onClick={() => navigate('/dashboard/recent')}
                        className={`flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all text-sm font-medium ${
                            location.pathname.includes('/recent') 
                                ? 'text-dn-text bg-dn-accent/10 active-nav-indicator scale-[0.98]' 
                                : 'text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text'
                        }`}
                    >
                        <span className={`material-symbols-outlined ${location.pathname.includes('/recent') ? 'text-dn-primary' : ''}`} style={{ fontVariationSettings: location.pathname.includes('/recent') ? "'FILL' 1" : "" }}>schedule</span>
                        <span>Recent</span>
                    </button>
                    <button 
                        onClick={() => navigate('/dashboard/shared')}
                        className={`flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all text-sm font-medium ${
                            location.pathname.includes('/shared') 
                                ? 'text-dn-text bg-dn-accent/10 active-nav-indicator scale-[0.98]' 
                                : 'text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text'
                        }`}
                    >
                        <span className={`material-symbols-outlined ${location.pathname.includes('/shared') ? 'text-dn-primary' : ''}`} style={{ fontVariationSettings: location.pathname.includes('/shared') ? "'FILL' 1" : "" }}>group</span>
                        <span>Shared</span>
                    </button>
                    <button 
                        onClick={() => navigate('/dashboard/trash')}
                        className={`flex items-center gap-3 px-3 py-2.5 rounded-lg transition-all text-sm font-medium ${
                            location.pathname.includes('/trash') 
                                ? 'text-dn-text bg-dn-accent/10 active-nav-indicator scale-[0.98]' 
                                : 'text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text'
                        }`}
                    >
                        <span className={`material-symbols-outlined ${location.pathname.includes('/trash') ? 'text-dn-primary' : ''}`} style={{ fontVariationSettings: location.pathname.includes('/trash') ? "'FILL' 1" : "" }}>delete</span>
                        <span>Trash</span>
                    </button>
                </nav>

                <div className="mt-auto px-2 space-y-4">
                    <button className="w-full dn-button-primary py-3 rounded-xl">Upgrade Storage</button>
                    
                    <div className="flex flex-col gap-1">
                        <div className={`flex items-center gap-3 px-2 py-1.5 rounded-lg transition-colors ${agent?.online ? 'text-dn-success bg-dn-success/5' : 'text-dn-error bg-dn-error/5'}`}>
                            <span className={`material-symbols-outlined text-sm ${agent?.online ? 'animate-pulse' : ''}`}>
                                {agent?.online ? 'cloud_done' : 'cloud_off'}
                            </span>
                            <span className="text-[10px] font-black uppercase tracking-tight">
                                {agent?.online ? 'Agent Online' : 'Agent Offline'}
                            </span>
                        </div>
                        
                        <button 
                            onClick={handleLogout}
                            className="flex items-center gap-3 px-2 py-1.5 text-dn-muted hover:text-dn-error hover:bg-dn-error/5 rounded-lg transition-all text-[10px] font-black uppercase tracking-widest"
                        >
                            <span className="material-symbols-outlined text-sm">logout</span>
                            <span>Sign Out</span>
                        </button>
                    </div>
                </div>
            </aside>

            {/* Main Content Area */}
            <main className="flex-1 ml-[200px] h-screen flex flex-col relative">
                <Outlet context={{ agent, user, fetchData }} />
            </main>
        </div>
    );
};

export default Dashboard;
