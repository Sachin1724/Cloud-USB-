import React from 'react';
import { useNavigate } from 'react-router-dom';

const Landing: React.FC = () => {
    const navigate = useNavigate();

    return (
        <div className="bg-dn-bg font-sans text-dn-text min-h-screen overflow-x-hidden">
            {/* TopNavBar */}
            <nav className="fixed top-0 w-full z-[100] h-20 bg-dn-bg/60 backdrop-blur-2xl border-b border-dn-border/10">
                <div className="flex justify-between items-center px-12 max-w-[1440px] mx-auto w-full h-full">
                    <div className="text-2xl font-black tracking-tighter text-dn-primary">DriveNet</div>
                    <div className="hidden md:flex items-center gap-10">
                        <a className="text-dn-primary border-b-2 border-dn-accent pb-1 font-medium text-sm transition-all duration-300" href="#">Solutions</a>
                        <a className="text-dn-subtext hover:text-dn-primary font-medium text-sm transition-all duration-300" href="#">Security</a>
                        <a className="text-dn-subtext hover:text-dn-primary font-medium text-sm transition-all duration-300" href="#">Pricing</a>
                    </div>
                    <div className="flex items-center gap-6">
                        <button onClick={() => navigate('/login')} className="text-dn-subtext hover:text-dn-primary font-medium text-sm transition-all duration-300">Sign In</button>
                        <button onClick={() => navigate('/login')} className="dn-button-primary">Get Started</button>
                    </div>
                </div>
            </nav>

            <main className="relative pt-32">
                {/* Background Ambient Glow */}
                <div className="absolute top-[-10%] left-1/2 -translate-x-1/2 w-[1000px] h-[600px] bg-dn-accent/10 blur-[120px] rounded-full -z-10" />

                {/* Hero Section */}
                <section className="max-w-7xl mx-auto px-12 text-center flex flex-col items-center">
                    <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-dn-surface-highest/50 border border-dn-border/20 mb-8">
                        <span className="w-2 h-2 rounded-full bg-dn-accent animate-pulse"></span>
                        <span className="text-[0.75rem] font-semibold tracking-widest uppercase text-dn-subtext">Private Network v2.4 Live</span>
                    </div>
                    
                    <h1 className="text-6xl md:text-8xl font-black tracking-tighter leading-tight mb-8 text-gradient">
                        Your Files. <br /> Anywhere.
                    </h1>
                    
                    <p className="max-w-2xl text-lg md:text-xl text-dn-subtext leading-relaxed mb-12">
                        Turn your PC into a private cloud. Access your entire file system from any browser, anywhere in the world with military-grade encryption.
                    </p>
                    
                    <div className="flex flex-wrap justify-center gap-6 mb-24">
                        <button onClick={() => navigate('/login')} className="px-8 py-4 bg-dn-accent text-white rounded-full font-bold text-lg hover:shadow-[0_0_20px_rgba(99,102,241,0.4)] transition-all duration-300 active:scale-95">
                            Connect Now
                        </button>
                        <button className="px-8 py-4 border border-dn-border/30 text-dn-text rounded-full font-bold text-lg hover:bg-white/5 transition-all duration-300 active:scale-95">
                            Download Agent
                        </button>
                    </div>

                    {/* UI Preview - Glassmorphism */}
                    <div className="w-full max-w-5xl glass-card rounded-2xl p-4 md:p-8 glow-subtle mb-32 overflow-hidden relative group">
                        <div className="flex items-center gap-4 border-b border-dn-border/10 pb-6 mb-6">
                            <div className="flex gap-1.5">
                                <div className="w-3 h-3 rounded-full bg-[#ff5f56]" />
                                <div className="w-3 h-3 rounded-full bg-[#ffbd2e]" />
                                <div className="w-3 h-3 rounded-full bg-[#27c93f]" />
                            </div>
                            <div className="flex-1 bg-dn-surface-lowest/50 rounded-lg py-1.5 px-4 text-xs text-dn-subtext/60 flex items-center gap-2">
                                <span className="material-symbols-outlined text-[14px]">lock</span>
                                https://drivenet.io/vault/desktop-pc
                            </div>
                        </div>
                        
                        <div className="grid grid-cols-12 gap-8 h-[400px]">
                            <div className="col-span-3 border-r border-dn-border/10 pr-4 hidden md:block text-left">
                                <ul className="space-y-2">
                                    <li className="bg-dn-accent/10 text-dn-primary px-3 py-2 rounded-lg text-sm font-medium flex items-center gap-3">
                                        <span className="material-symbols-outlined text-[18px]">home</span> Dashboard
                                    </li>
                                    <li className="text-dn-subtext hover:text-dn-text px-3 py-2 rounded-lg text-sm font-medium flex items-center gap-3 transition-colors">
                                        <span className="material-symbols-outlined text-[18px]">folder</span> Root Directory
                                    </li>
                                    <li className="text-dn-subtext hover:text-dn-text px-3 py-2 rounded-lg text-sm font-medium flex items-center gap-3 transition-colors">
                                        <span className="material-symbols-outlined text-[18px]">cloud</span> Shared Links
                                    </li>
                                </ul>
                            </div>
                            <div className="col-span-12 md:col-span-9">
                                <div className="grid grid-cols-2 lg:grid-cols-3 gap-6 text-left">
                                    <div className="bg-dn-surface-highest/30 p-4 rounded-xl border border-dn-border/10 group-hover:border-dn-accent/30 transition-all">
                                        <div className="w-12 h-12 bg-dn-accent/10 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
                                            <span className="material-symbols-outlined text-dn-accent">description</span>
                                        </div>
                                        <div className="text-sm font-semibold mb-1">Q4_Report.pdf</div>
                                        <div className="text-xs text-dn-subtext">12.4 MB • 2h ago</div>
                                    </div>
                                    <div className="bg-dn-surface-highest/30 p-4 rounded-xl border border-dn-border/10 group-hover:border-dn-accent/30 transition-all">
                                        <div className="w-12 h-12 bg-dn-primary/10 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
                                            <span className="material-symbols-outlined text-dn-primary">image</span>
                                        </div>
                                        <div className="text-sm font-semibold mb-1">Architecture_Photos</div>
                                        <div className="text-xs text-dn-subtext">42 Items • Yesterday</div>
                                    </div>
                                    <div className="bg-dn-surface-highest/30 p-4 rounded-xl border border-dn-border/10 group-hover:border-dn-accent/30 transition-all">
                                        <div className="w-12 h-12 bg-dn-text/10 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform">
                                            <span className="material-symbols-outlined text-dn-text">code</span>
                                        </div>
                                        <div className="text-sm font-semibold mb-1">App_Source.zip</div>
                                        <div className="text-xs text-dn-subtext">1.2 GB • 3d ago</div>
                                    </div>
                                </div>
                            </div>
                        </div>

                        {/* Bottom Status Bar */}
                        <div className="absolute bottom-0 left-0 w-full px-8 py-3 bg-dn-accent/5 flex items-center justify-between text-[10px] uppercase tracking-widest font-bold text-dn-primary/60">
                            <span>Active Connection: Desktop-WKS-01</span>
                            <span className="flex items-center gap-2">
                                <span className="w-1.5 h-1.5 bg-dn-success rounded-full"></span> Secure Tunnel Established
                            </span>
                        </div>
                    </div>
                </section>

                {/* Features Section */}
                <section className="max-w-7xl mx-auto px-12 pb-32">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
                        <div className="glass-card p-8 rounded-xl hover:border-dn-accent/20 transition-all duration-500 group">
                            <div className="mb-6 p-3 bg-dn-surface-low rounded-lg w-fit group-hover:bg-dn-accent/20 transition-colors">
                                <span className="material-symbols-outlined text-dn-accent text-3xl">shield</span>
                            </div>
                            <h3 className="text-xl font-bold mb-4 tracking-tight">Security</h3>
                            <p className="text-dn-subtext leading-relaxed">
                                End-to-end encrypted tunnels ensure your data never touches our servers. Your PC, your rules.
                            </p>
                        </div>
                        <div className="glass-card p-8 rounded-xl hover:border-dn-accent/20 transition-all duration-500 group">
                            <div className="mb-6 p-3 bg-dn-surface-low rounded-lg w-fit group-hover:bg-dn-accent/20 transition-colors">
                                <span className="material-symbols-outlined text-dn-accent text-3xl">language</span>
                            </div>
                            <h3 className="text-xl font-bold mb-4 tracking-tight">Global Access</h3>
                            <p className="text-dn-subtext leading-relaxed">
                                No matter where you are, connect via any web browser. No complicated VPN setup required.
                            </p>
                        </div>
                        <div className="glass-card p-8 rounded-xl hover:border-dn-accent/20 transition-all duration-500 group">
                            <div className="mb-6 p-3 bg-dn-surface-low rounded-lg w-fit group-hover:bg-dn-accent/20 transition-colors">
                                <span className="material-symbols-outlined text-dn-accent text-3xl">sync</span>
                            </div>
                            <h3 className="text-xl font-bold mb-4 tracking-tight">Real-time Sync</h3>
                            <p className="text-dn-subtext leading-relaxed">
                                Instant file indexing and high-speed streaming for large media assets straight from your hardware.
                            </p>
                        </div>
                    </div>
                </section>

                {/* Stats Section */}
                <section className="max-w-7xl mx-auto px-12 pb-32">
                    <div className="bg-dn-surface-low rounded-2xl p-12 flex flex-col md:flex-row justify-around items-center border border-dn-border/5">
                        <div className="text-center mb-8 md:mb-0">
                            <div className="text-5xl font-black text-dn-accent mb-2 tracking-tighter">0%</div>
                            <p className="text-xs uppercase tracking-widest font-semibold text-dn-subtext">Cloud Storage Fees</p>
                        </div>
                        <div className="w-px h-12 bg-dn-border/10 hidden md:block" />
                        <div className="text-center mb-8 md:mb-0">
                            <div className="text-5xl font-black text-dn-accent mb-2 tracking-tighter">AES-256</div>
                            <p className="text-xs uppercase tracking-widest font-semibold text-dn-subtext">Native Encryption</p>
                        </div>
                        <div className="w-px h-12 bg-dn-border/10 hidden md:block" />
                        <div className="text-center">
                            <div className="text-5xl font-black text-dn-accent mb-2 tracking-tighter">&lt; 10ms</div>
                            <p className="text-xs uppercase tracking-widest font-semibold text-dn-subtext">Average Latency</p>
                        </div>
                    </div>
                </section>

                {/* CTA Section */}
                <section className="pb-40 text-center px-12">
                    <div className="relative py-24 overflow-hidden rounded-3xl bg-dn-accent/5 border border-dn-accent/10">
                        <div className="absolute inset-0 bg-gradient-to-t from-transparent to-dn-accent/5 pointer-events-none" />
                        <h2 className="text-4xl md:text-5xl font-black tracking-tight mb-8 relative z-10">Ready to take control of your data?</h2>
                        <button onClick={() => navigate('/login')} className="relative z-10 px-10 py-5 bg-dn-accent-container text-dn-bg rounded-full font-bold text-xl hover:bg-dn-primary transition-all duration-300 active:scale-95 shadow-xl shadow-dn-accent/20">
                            Get Started for Free
                        </button>
                    </div>
                </section>
            </main>

            {/* Footer */}
            <footer className="w-full py-16 border-t border-dn-border/10 bg-dn-bg/80">
                <div className="flex flex-col md:flex-row justify-between items-center px-12 max-w-7xl mx-auto gap-8">
                    <div className="text-dn-primary font-bold tracking-widest uppercase">DriveNet</div>
                    <div className="flex flex-wrap justify-center gap-10">
                        <a className="text-[0.75rem] uppercase tracking-widest font-semibold text-dn-subtext hover:text-dn-primary transition-colors" href="#">Privacy Policy</a>
                        <a className="text-[0.75rem] uppercase tracking-widest font-semibold text-dn-subtext hover:text-dn-primary transition-colors" href="#">Service Terms</a>
                        <a className="text-[0.75rem] uppercase tracking-widest font-semibold text-dn-subtext hover:text-dn-primary transition-colors" href="#">Infrastructure</a>
                        <a className="text-[0.75rem] uppercase tracking-widest font-semibold text-dn-subtext hover:text-dn-primary transition-colors" href="#">Documentation</a>
                    </div>
                    <p className="text-[0.75rem] uppercase tracking-widest font-semibold text-dn-accent opacity-80">
                        © 2024 DriveNet. Your data, evolved.
                    </p>
                </div>
            </footer>
        </div>
    );
};

export default Landing;
