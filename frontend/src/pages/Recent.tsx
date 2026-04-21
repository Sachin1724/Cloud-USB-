import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { useOutletContext, useNavigate } from 'react-router-dom';

interface RecentItem {
    name: string;
    path: string;
    is_dir: boolean;
    size: number;
    modified: number;
}

const Recent: React.FC = () => {
    const RAW_API = (import.meta as any).env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    const { agent } = useOutletContext<any>();
    const navigate = useNavigate();

    const [items, setItems] = useState<RecentItem[]>([]);
    const [loading, setLoading] = useState(true);

    const fetchRecent = async () => {
        if (!agent?.drive) return;
        setLoading(true);
        try {
            const token = localStorage.getItem('drivenet_token');
            const res = await axios.get(`${API}/api/fs/me/recent`, {
                headers: { Authorization: `Bearer ${token}` },
                params: { drive: agent.drive }
            });
            setItems(res.data.items || []);
        } catch (err) {
            console.error('Fetch recent error:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchRecent();
    }, [agent?.drive]);

    const formatTimeAgo = (ms: number) => {
        const diff = Date.now() - ms;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);

        if (days > 0) return `${days}d ago`;
        if (hours > 0) return `${hours}h ago`;
        if (minutes > 0) return `${minutes}m ago`;
        return 'Just now';
    };

    return (
        <div className="flex-1 flex flex-col h-full bg-dn-bg overflow-hidden">
            <header className="h-16 px-8 flex items-center border-b border-dn-border/10 bg-dn-bg/80 backdrop-blur-md">
                <span className="text-[10px] font-black uppercase tracking-widest text-dn-accent">Activity Feed</span>
            </header>

            <div className="flex-1 overflow-y-auto p-8 custom-scrollbar">
                <div className="mb-8">
                    <h2 className="text-2xl font-black text-dn-text">Recently Modified</h2>
                    <p className="text-dn-subtext text-xs mt-1">Automatic sync history across your private cloud</p>
                </div>

                {loading ? (
                    <div className="flex flex-col items-center justify-center py-32 gap-4">
                        <div className="w-8 h-8 border-2 border-dn-accent/20 border-t-dn-accent rounded-full animate-spin" />
                    </div>
                ) : items.length === 0 ? (
                    <div className="py-32 text-center opacity-30">
                        <span className="material-symbols-outlined text-6xl mb-4">history</span>
                        <p className="text-xs font-bold uppercase tracking-widest">No recent activity detected</p>
                    </div>
                ) : (
                    <div className="flex flex-col gap-3">
                        {items.map((item, idx) => (
                            <div 
                                key={idx}
                                onClick={() => navigate(`/dashboard/files?drive=${encodeURIComponent(agent.drive)}&path=${encodeURIComponent(item.path)}`)}
                                className="group flex items-center justify-between p-4 bg-dn-surface-low rounded-2xl border border-dn-border/5 hover:border-dn-accent/30 transition-all cursor-pointer"
                            >
                                <div className="flex items-center gap-4">
                                    <div className="w-10 h-10 rounded-xl bg-dn-surface-highest flex items-center justify-center text-dn-subtext group-hover:text-dn-accent transition-colors">
                                        <span className="material-symbols-outlined">
                                            {item.is_dir ? 'folder' : 'description'}
                                        </span>
                                    </div>
                                    <div className="flex flex-col">
                                        <span className="text-sm font-bold text-dn-text truncate max-w-sm">{item.name}</span>
                                        <div className="flex items-center gap-2 text-[10px] text-dn-subtext font-bold uppercase tracking-tighter opacity-60">
                                            <span>{formatTimeAgo(item.modified)}</span>
                                            <span className="w-1 h-1 bg-dn-muted/30 rounded-full" />
                                            <span className="truncate max-w-[200px]">{item.path || 'Root'}</span>
                                        </div>
                                    </div>
                                </div>
                                <span className="material-symbols-outlined text-dn-muted opacity-0 group-hover:opacity-100 transition-opacity">navigate_next</span>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div>
    );
};

export default Recent;
