import React, { useState, useEffect, useMemo } from 'react';
import axios from 'axios';
import { useNavigate, useLocation } from 'react-router-dom';

interface FileItem {
  name: string;
  is_dir: boolean;
  size: number;
  modified: string;
  path: string;
  drive?: string;
}

const FileBrowser: React.FC = () => {
    const RAW_API = import.meta.env.VITE_API_URL || 'http://localhost:8000';
    const API = RAW_API.endsWith('/') ? RAW_API.slice(0, -1) : RAW_API;
    const navigate = useNavigate();
    const location = useLocation();

    const [files, setFiles] = useState<FileItem[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [searchQuery, setSearchQuery] = useState('');
    const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

    const queryParams = new URLSearchParams(location.search);
    const currentPath = queryParams.get('path') || '';
    const currentDrive = queryParams.get('drive') || '';

    const fetchFiles = async () => {
        setLoading(true);
        setError('');
        const token = localStorage.getItem('drivenet_token');
        try {
            const res = await axios.get(`${API}/api/fs/list`, {
                headers: { Authorization: `Bearer ${token}` },
                params: { path: currentPath, drive: currentDrive }
            });
            setFiles(res.data.files || []);
        } catch (err: any) {
            setError(err.response?.data?.error || 'Failed to fetch files');
            if (err.response?.status === 401) {
                localStorage.removeItem('drivenet_token');
                navigate('/login');
            }
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchFiles();
    }, [currentPath, currentDrive]);

    const filteredFiles = useMemo(() => {
        return files.filter(f => f.name.toLowerCase().includes(searchQuery.toLowerCase()));
    }, [files, searchQuery]);

    const handleNavigate = (item: FileItem) => {
        if (item.is_dir) {
            const newPath = item.path;
            const newDrive = item.drive || currentDrive;
            navigate(`?drive=${encodeURIComponent(newDrive)}&path=${encodeURIComponent(newPath)}`);
        }
    };

    const breadcrumbs = useMemo(() => {
        const parts = currentPath.split(/[/\\]/).filter(Boolean);
        return [{ name: 'Home', path: '', drive: currentDrive }, ...parts.map((p, i) => ({
            name: p,
            path: parts.slice(0, i + 1).join('/'),
            drive: currentDrive
        }))];
    }, [currentPath, currentDrive]);

    const getFileIcon = (item: FileItem) => {
        if (item.is_dir) return 'folder';
        const ext = item.name.split('.').pop()?.toLowerCase();
        if (['jpg', 'jpeg', 'png', 'svg', 'webp'].includes(ext!)) return 'image';
        if (['mp4', 'mov', 'avi', 'mkv'].includes(ext!)) return 'video_file';
        if (['pdf', 'doc', 'docx', 'txt'].includes(ext!)) return 'description';
        if (['zip', 'rar', '7z', 'tar'].includes(ext!)) return 'inventory_2';
        return 'insert_drive_file';
    };

    const formatSize = (bytes: number) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    };

    return (
        <div className="flex min-h-screen bg-dn-bg overflow-hidden">
            {/* Sidebar */}
            <aside className="fixed left-0 top-0 h-screen w-[220px] z-50 glass-sidebar flex flex-col py-8 px-4 gap-10">
                <div className="px-2">
                    <span className="text-xl font-black tracking-tighter text-dn-text">DriveNet Explorer</span>
                    <div className="flex items-center gap-3 mt-8 p-2 rounded-xl hover:bg-white/5 transition-colors cursor-pointer">
                        <div className="w-8 h-8 rounded-full bg-dn-accent/20 flex items-center justify-center text-dn-accent font-bold text-xs uppercase">U</div>
                        <div className="flex flex-col overflow-hidden">
                            <span className="text-xs font-semibold truncate text-dn-text">User</span>
                            <span className="text-[10px] text-dn-subtext uppercase tracking-wider font-bold">Pro Account</span>
                        </div>
                    </div>
                </div>

                <nav className="flex flex-col gap-1 flex-1">
                    <button className="relative flex items-center gap-3 px-3 py-2.5 text-dn-text bg-dn-accent/10 active-nav-indicator rounded-lg transition-all scale-[0.98] text-sm font-medium">
                        <span className="material-symbols-outlined text-dn-primary" style={{ fontVariationSettings: "'FILL' 1" }}>folder</span>
                        <span>My Files</span>
                    </button>
                    <button className="flex items-center gap-3 px-3 py-2.5 text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text rounded-lg transition-colors text-sm font-medium">
                        <span className="material-symbols-outlined">schedule</span>
                        <span>Recent</span>
                    </button>
                    <button className="flex items-center gap-3 px-3 py-2.5 text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text rounded-lg transition-colors text-sm font-medium">
                        <span className="material-symbols-outlined">group</span>
                        <span>Shared</span>
                    </button>
                    <button className="flex items-center gap-3 px-3 py-2.5 text-dn-subtext hover:bg-dn-surface-low hover:text-dn-text rounded-lg transition-colors text-sm font-medium">
                        <span className="material-symbols-outlined">delete</span>
                        <span>Trash</span>
                    </button>
                </nav>

                <div className="mt-auto px-2">
                    <button className="w-full dn-button-primary py-3 rounded-xl mb-4">Upgrade Storage</button>
                    <div className="flex items-center gap-3 px-2 py-2 text-dn-subtext opacity-60">
                        <span className="material-symbols-outlined text-sm">cloud_done</span>
                        <span className="text-[11px] font-bold uppercase tracking-tight">Cloud Active</span>
                    </div>
                </div>
            </aside>

            {/* Main Content */}
            <main className="flex-1 ml-[220px] h-screen flex flex-col relative">
                {/* Header */}
                <header className="sticky top-0 w-full z-40 bg-dn-bg/80 backdrop-blur-md flex justify-between items-center h-16 px-8 border-b border-dn-border/10">
                    <div className="flex items-center gap-6 overflow-hidden">
                        <span className="text-[10px] font-bold uppercase tracking-widest text-dn-accent whitespace-nowrap">All Files</span>
                        <div className="h-4 w-px bg-dn-border/30 shrink-0" />
                        <div className="flex items-center gap-2 text-xs font-medium text-dn-subtext overflow-hidden">
                            {breadcrumbs.map((b, i) => (
                                <React.Fragment key={i}>
                                    <button 
                                        onClick={() => navigate(`?drive=${encodeURIComponent(b.drive)}&path=${encodeURIComponent(b.path)}`)}
                                        className={`hover:text-dn-text whitespace-nowrap ${i === breadcrumbs.length - 1 ? 'text-dn-text font-bold' : ''}`}
                                    >
                                        {b.name}
                                    </button>
                                    {i < breadcrumbs.length - 1 && <span className="material-symbols-outlined text-[14px]">chevron_right</span>}
                                </React.Fragment>
                            ))}
                        </div>
                    </div>

                    <div className="flex items-center gap-4 flex-1 justify-end max-w-2xl">
                        <div className="relative w-full max-w-md hidden md:block">
                            <span className="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-dn-muted text-sm">search</span>
                            <input 
                                className="w-full bg-dn-surface-lowest border-none rounded-full py-2 pl-10 pr-4 text-sm focus:ring-1 focus:ring-dn-accent/30 transition-all placeholder:text-dn-muted/50 text-dn-text"
                                placeholder="Search files, folders..."
                                type="text"
                                value={searchQuery}
                                onChange={(e) => setSearchQuery(e.target.value)}
                            />
                        </div>
                        <div className="flex items-center gap-2">
                            <button onClick={() => navigate('/login')} className="p-2 text-dn-subtext hover:bg-dn-surface-high rounded-lg transition-all active:scale-95">
                                <span className="material-symbols-outlined">logout</span>
                            </button>
                        </div>
                    </div>
                </header>

                {/* Workspace */}
                <div className="flex-1 overflow-y-auto p-8 bg-dn-bg custom-scrollbar">
                    {/* Toolbar */}
                    <div className="flex items-center justify-between mb-8">
                        <div className="flex items-center gap-3">
                            <div className="flex bg-dn-surface-low p-1 rounded-lg">
                                <button 
                                    onClick={() => setViewMode('grid')}
                                    className={`flex items-center justify-center p-2 rounded-md ${viewMode === 'grid' ? 'bg-dn-surface-highest text-dn-primary shadow-sm' : 'text-dn-subtext hover:text-dn-text'}`}
                                >
                                    <span className="material-symbols-outlined text-[20px]">grid_view</span>
                                </button>
                                <button 
                                    onClick={() => setViewMode('list')}
                                    className={`flex items-center justify-center p-2 rounded-md ${viewMode === 'list' ? 'bg-dn-surface-highest text-dn-primary shadow-sm' : 'text-dn-subtext hover:text-dn-text'}`}
                                >
                                    <span className="material-symbols-outlined text-[20px]">list</span>
                                </button>
                            </div>
                            <div className="flex items-center gap-2 px-4 py-2 bg-dn-surface-low rounded-lg text-xs font-bold uppercase tracking-widest text-dn-subtext cursor-pointer hover:bg-dn-surface-high transition-colors">
                                <span>Recent</span>
                                <span className="material-symbols-outlined text-[18px]">expand_more</span>
                            </div>
                        </div>

                        <div className="flex items-center gap-2 px-3 py-1.5 bg-dn-success/5 border border-dn-success/20 rounded-full">
                            <span className="w-1.5 h-1.5 bg-dn-success rounded-full animate-pulse" />
                            <span className="text-[9px] font-black uppercase tracking-widest text-dn-success">Tunnel Active</span>
                        </div>
                    </div>

                    {loading ? (
                        <div className="flex flex-col items-center justify-center h-64 gap-4">
                            <div className="w-10 h-10 border-4 border-dn-accent/20 border-t-dn-accent rounded-full animate-spin" />
                            <span className="text-xs font-bold uppercase tracking-widest text-dn-muted">Accessing Vault...</span>
                        </div>
                    ) : error ? (
                        <div className="bg-dn-error/5 border border-dn-error/20 p-8 rounded-2xl text-center">
                            <span className="material-symbols-outlined text-dn-error text-5xl mb-4">error</span>
                            <h3 className="text-xl font-bold mb-2">Access Denied</h3>
                            <p className="text-dn-subtext text-sm mb-6">{error}</p>
                            <button onClick={fetchFiles} className="dn-button-secondary">Retry Connection</button>
                        </div>
                    ) : (
                        <div className={viewMode === 'grid' 
                            ? "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-6"
                            : "flex flex-col gap-2"
                        }>
                            {filteredFiles.map((file, idx) => (
                                <div 
                                    key={idx}
                                    onClick={() => handleNavigate(file)}
                                    className={`group relative bg-dn-surface-low rounded-xl transition-all duration-300 cursor-pointer overflow-hidden ${
                                        viewMode === 'grid' 
                                            ? 'p-5 border border-dn-border/5 hover:border-dn-accent/30 hover:shadow-dn-glow' 
                                            : 'p-3 flex items-center justify-between border-b border-dn-border/10 hover:bg-dn-surface-high'
                                    }`}
                                >
                                    {viewMode === 'grid' ? (
                                        <>
                                            <div className="flex items-start justify-between mb-4">
                                                <div className={`p-3 rounded-xl ${file.is_dir ? 'bg-dn-accent/10' : 'bg-dn-surface-highest'}`}>
                                                    <span className={`material-symbols-outlined text-3xl ${file.is_dir ? 'text-dn-accent' : 'text-dn-subtext'}`} style={{ fontVariationSettings: file.is_dir ? "'FILL' 1" : "" }}>
                                                        {getFileIcon(file)}
                                                    </span>
                                                </div>
                                                <button className="text-dn-muted opacity-0 group-hover:opacity-100 transition-opacity">
                                                    <span className="material-symbols-outlined">more_vert</span>
                                                </button>
                                            </div>
                                            <div>
                                                <h3 className="text-dn-text font-semibold text-sm mb-1 truncate" title={file.name}>{file.name}</h3>
                                                <p className="text-dn-subtext text-[10px] font-bold uppercase tracking-tight flex items-center gap-2">
                                                    <span>{file.is_dir ? 'Folder' : formatSize(file.size)}</span>
                                                    <span className="w-1 h-1 bg-dn-muted/30 rounded-full" />
                                                    <span>{new Date(file.modified).toLocaleDateString()}</span>
                                                </p>
                                            </div>
                                        </>
                                    ) : (
                                        <>
                                            <div className="flex items-center gap-4 flex-1 overflow-hidden">
                                                <span className={`material-symbols-outlined ${file.is_dir ? 'text-dn-accent' : 'text-dn-subtext'}`} style={{ fontVariationSettings: file.is_dir ? "'FILL' 1" : "" }}>
                                                    {getFileIcon(file)}
                                                </span>
                                                <span className="text-sm font-medium truncate text-dn-text">{file.name}</span>
                                            </div>
                                            <div className="flex items-center gap-6 text-[10px] font-bold uppercase tracking-tight text-dn-subtext">
                                                <span className="w-20 text-right">{file.is_dir ? '--' : formatSize(file.size)}</span>
                                                <span className="w-24 text-right">{new Date(file.modified).toLocaleDateString()}</span>
                                            </div>
                                        </>
                                    )}
                                </div>
                            ))}
                            
                            {filteredFiles.length === 0 && (
                                <div className="col-span-full py-20 flex flex-col items-center justify-center opacity-40">
                                    <span className="material-symbols-outlined text-7xl mb-4">folder_open</span>
                                    <p className="text-sm font-bold uppercase tracking-widest text-dn-subtext">No files found in the vault</p>
                                </div>
                            )}
                        </div>
                    )}
                </div>

                {/* Storage Info Bento */}
                <div className="px-8 pb-8 bg-dn-bg grid grid-cols-1 md:grid-cols-3 gap-6">
                    <div className="bg-dn-surface-low p-6 rounded-2xl border border-dn-border/5">
                        <h4 className="text-[10px] font-bold uppercase tracking-widest text-dn-subtext mb-4">Vault Integrity</h4>
                        <div className="flex items-end gap-3 mb-2">
                            <span className="text-3xl font-black text-dn-text">Secure</span>
                        </div>
                        <p className="text-[10px] text-dn-muted uppercase font-bold tracking-tight">Active End-to-End Tunneling</p>
                    </div>
                </div>
            </main>
        </div>
    );
};

export default FileBrowser;
