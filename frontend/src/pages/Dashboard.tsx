import React, { useState } from 'react';
import { useNavigate, Outlet, useLocation } from 'react-router-dom';

const Dashboard: React.FC = () => {
    const navigate = useNavigate();
    const location = useLocation();
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);

    const handleLogout = () => {
        localStorage.removeItem('drivenet_token');
        navigate('/login');
    };

    const navItems = [
        { icon: 'dashboard', label: 'Overview', path: '/dashboard' },
        { icon: 'folder_open', label: 'Files', path: '/dashboard/files' },
    ];

    return (
        <div className="bg-surface-900 font-sans text-white min-h-screen flex flex-col overflow-x-hidden">
            {/* Top Navigation */}
            <header className="relative z-20 flex items-center justify-between glass border-b border-white/[0.06] px-4 sm:px-6 py-3">
                <div className="flex items-center gap-4">
                    <button
                        className="md:hidden text-white/50 hover:text-white transition-colors"
                        onClick={() => setIsSidebarOpen(!isSidebarOpen)}
                    >
                        <span className="material-symbols-outlined text-2xl">menu</span>
                    </button>
                    <div className="flex items-center gap-2.5">
                        <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-primary to-primary-dark flex items-center justify-center">
                            <span className="material-symbols-outlined text-white text-lg">cloud_upload</span>
                        </div>
                        <span className="text-lg font-bold tracking-tight">DriveNet</span>
                    </div>
                </div>

                <div className="flex items-center gap-3">
                    {/* Connection Status */}
                    <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-full bg-green-400/10 border border-green-400/20">
                        <span className="w-2 h-2 rounded-full bg-green-400 animate-pulse"></span>
                        <span className="text-xs font-medium text-green-400/80">Agent Online</span>
                    </div>
                    <button
                        onClick={handleLogout}
                        className="w-9 h-9 flex items-center justify-center rounded-xl bg-white/[0.04] hover:bg-white/[0.08] text-white/40 hover:text-white transition-all"
                        title="Logout"
                    >
                        <span className="material-symbols-outlined text-xl">logout</span>
                    </button>
                </div>
            </header>

            <div className="flex flex-1 overflow-hidden relative">
                {/* Mobile Overlay */}
                {isSidebarOpen && (
                    <div
                        className="fixed inset-0 bg-black/60 z-20 md:hidden backdrop-blur-sm"
                        onClick={() => setIsSidebarOpen(false)}
                    />
                )}

                {/* Sidebar */}
                <aside className={`fixed md:relative z-30 w-60 h-full bg-surface-950/80 backdrop-blur-xl border-r border-white/[0.06] flex flex-col py-6 transition-transform duration-300 ease-out ${isSidebarOpen ? 'translate-x-0' : '-translate-x-full'} md:translate-x-0`}>
                    <div className="px-4 mb-2">
                        <p className="text-[11px] font-semibold text-white/20 uppercase tracking-wider px-3 mb-3">Navigation</p>
                        <nav className="flex flex-col gap-1">
                            {navItems.map((item) => (
                                <a
                                    key={item.path}
                                    onClick={() => { navigate(item.path); setIsSidebarOpen(false); }}
                                    className={`flex items-center gap-3 px-3 py-2.5 rounded-xl cursor-pointer transition-all text-sm font-medium ${
                                        location.pathname === item.path
                                            ? 'bg-primary/10 text-primary'
                                            : 'text-white/40 hover:text-white/70 hover:bg-white/[0.04]'
                                    }`}
                                >
                                    <span className="material-symbols-outlined text-xl">{item.icon}</span>
                                    <span>{item.label}</span>
                                </a>
                            ))}
                        </nav>
                    </div>

                    {/* Bottom Info */}
                    <div className="mt-auto px-4">
                        <div className="p-4 rounded-xl bg-white/[0.02] border border-white/[0.06]">
                            <div className="flex items-center gap-2 mb-2">
                                <span className="material-symbols-outlined text-primary text-lg">info</span>
                                <span className="text-xs font-semibold text-white/50">Connection</span>
                            </div>
                            <p className="text-[11px] text-white/25 leading-relaxed">
                                Secure tunnel active. Your files are encrypted end-to-end.
                            </p>
                        </div>
                    </div>
                </aside>

                {/* Main Content */}
                <main className="flex-1 overflow-y-auto overflow-x-hidden relative w-full">
                    <Outlet />
                </main>
            </div>
        </div>
    );
};

export default Dashboard;
