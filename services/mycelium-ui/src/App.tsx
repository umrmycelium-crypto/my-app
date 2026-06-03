import { useState, useEffect } from 'react'
import { 
  Activity, 
  Database, 
  Settings, 
  Terminal, 
  Send, 
  ShieldCheck, 
  AlertCircle,
  LayoutDashboard,
  Box,
  Cpu
} from 'lucide-react'
import { api } from './api'

function App() {
  const [activeTab, setActiveTab] = useState('dashboard')
  const [health, setHealth] = useState<any>(null)
  const [payload, setPayload] = useState<string>('{\n  "type": "battery_pack",\n  "attributes": {\n    "scuffing_score": 0.8,\n    "wear_score": 0.4,\n    "color": "black"\n  },\n  "confidence": 0.95\n}')
  const [response, setResponse] = useState<any>(null)
  const [isLoading, setIsLoading] = useState(false)

  useEffect(() => {
    const fetchHealth = async () => {
      const data = await api.getHealth()
      setHealth(data)
    }
    fetchHealth()
    const interval = setInterval(fetchHealth, 30000)
    return () => clearInterval(interval)
  }, [])

  const handleSubmit = async () => {
    setIsLoading(true)
    try {
      const data = JSON.parse(payload)
      const res = await api.detect(data)
      setResponse(res)
      setActiveTab('terminal')
    } catch (e) {
      setResponse({ error: 'Invalid JSON or API error', details: String(e) })
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="flex h-screen bg-[#0f172a] text-slate-200 overflow-hidden font-sans">
      {/* Sidebar */}
      <div className="w-64 bg-[#1e293b] border-r border-slate-700/50 flex flex-col">
        <div className="p-6 flex items-center gap-3 border-b border-slate-700/50">
          <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center shadow-lg shadow-blue-500/20">
            <Box size={20} className="text-white" />
          </div>
          <h1 className="font-bold text-lg tracking-tight">MYCELIUM UI</h1>
        </div>
        
        <nav className="flex-1 p-4 space-y-2 overflow-y-auto">
          <NavItem 
            active={activeTab === 'dashboard'} 
            onClick={() => setActiveTab('dashboard')}
            icon={<LayoutDashboard size={18} />}
            label="Dashboard"
          />
          <NavItem 
            active={activeTab === 'detections'} 
            onClick={() => setActiveTab('detections')}
            icon={<Activity size={18} />}
            label="Detections"
          />
          <NavItem 
            active={activeTab === 'entities'} 
            onClick={() => setActiveTab('entities')}
            icon={<Database size={18} />}
            label="Entity Store"
          />
          <NavItem 
            active={activeTab === 'rules'} 
            onClick={() => setActiveTab('rules')}
            icon={<ShieldCheck size={18} />}
            label="Rule Engine"
          />
          <div className="pt-4 pb-2 text-xs font-semibold text-slate-500 uppercase tracking-wider pl-4">
            System
          </div>
          <NavItem 
            active={activeTab === 'input'} 
            onClick={() => setActiveTab('input')}
            icon={<Send size={18} />}
            label="Direct Output"
          />
          <NavItem 
            active={activeTab === 'terminal'} 
            onClick={() => setActiveTab('terminal')}
            icon={<Terminal size={18} />}
            label="API Console"
          />
          <NavItem 
            active={activeTab === 'settings'} 
            onClick={() => setActiveTab('settings')}
            icon={<Settings size={18} />}
            label="Settings"
          />
        </nav>

        <div className="p-4 border-t border-slate-700/50 bg-[#0f172a]/30">
          <div className="flex items-center gap-3">
            <div className={`w-2 h-2 rounded-full ${health?.status === 'healthy' ? 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.5)]' : 'bg-rose-500 shadow-[0_0_8px_rgba(244,63,94,0.5)]'}`} />
            <span className="text-sm font-medium text-slate-400">
              {health?.status === 'healthy' ? 'Stack Healthy' : 'Service Alert'}
            </span>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <main className="flex-1 overflow-y-auto bg-gradient-to-br from-[#0f172a] to-[#1e293b]">
        <header className="h-16 border-b border-slate-700/50 flex items-center justify-between px-8 backdrop-blur-md sticky top-0 z-10">
          <h2 className="text-xl font-semibold capitalize text-slate-100">{activeTab.replace('-', ' ')}</h2>
          <div className="flex items-center gap-4">
             <div className="text-sm bg-[#334155] px-3 py-1 rounded-full text-slate-300 font-mono">
                v1.0.0-PROTOTYPE
             </div>
          </div>
        </header>

        <div className="p-8 max-w-6xl mx-auto">
          {activeTab === 'dashboard' && (
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
              <StatCard 
                title="Active Entities" 
                value="1,284" 
                change="+12%" 
                icon={<Database className="text-blue-400" />}
              />
              <StatCard 
                title="System Throughput" 
                value="42.5 req/s" 
                change="+5.2%" 
                icon={<Activity className="text-blue-400" />}
              />
              <StatCard 
                title="Active Rules" 
                value="56" 
                change="0%" 
                icon={<ShieldCheck className="text-blue-400" />}
              />
              
              <div className="col-span-1 md:col-span-2 bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-6 backdrop-blur-sm">
                <h3 className="text-lg font-medium mb-4 flex items-center gap-2">
                   <Activity size={20} className="text-blue-500" />
                   Recent Activity
                </h3>
                <div className="space-y-4">
                  {[1, 2, 3, 4].map((i) => (
                    <div key={i} className="flex items-center justify-between p-3 bg-[#0f172a]/50 rounded-lg border border-slate-700/30">
                      <div className="flex items-center gap-3">
                        <div className="p-2 bg-slate-800 rounded-md">
                          <Cpu size={16} className="text-slate-400" />
                        </div>
                        <div>
                          <p className="text-sm font-medium">Rule Match: Battery Wear</p>
                          <p className="text-xs text-slate-500">Entity: UUID-4829-XJ2</p>
                        </div>
                      </div>
                      <span className="text-xs text-slate-500">2m ago</span>
                    </div>
                  ))}
                </div>
              </div>

              <div className="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-6 backdrop-blur-sm">
                <h3 className="text-lg font-medium mb-4 flex items-center gap-2">
                   <AlertCircle size={20} className="text-amber-500" />
                   System Health
                </h3>
                <div className="space-y-3">
                  <HealthItem label="Rule Engine" status="online" />
                  <HealthItem label="PostgreSQL" status="online" />
                  <HealthItem label="Milvus" status="online" />
                  <HealthItem label="Elasticsearch" status="online" />
                  <HealthItem label="Redis" status="online" />
                </div>
              </div>
            </div>
          )}

          {activeTab === 'input' && (
            <div className="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-8 backdrop-blur-sm max-w-2xl mx-auto">
              <div className="mb-6">
                <h3 className="text-xl font-semibold mb-2">Direct Output Interface</h3>
                <p className="text-slate-400">Submit raw detection data directly to the Mycelium Rule Engine.</p>
              </div>

              <div className="space-y-6">
                <div>
                  <label className="block text-sm font-medium text-slate-300 mb-2 font-mono">Payload (JSON)</label>
                  <textarea 
                    value={payload}
                    onChange={(e) => setPayload(e.target.value)}
                    rows={10}
                    className="w-full bg-[#0f172a] border border-slate-700 rounded-lg p-4 font-mono text-sm text-blue-300 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition-all"
                  />
                </div>
                
                <button 
                  onClick={handleSubmit}
                  disabled={isLoading}
                  className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-slate-700 disabled:cursor-not-allowed text-white font-semibold py-3 px-6 rounded-lg shadow-lg shadow-blue-600/20 transition-all flex items-center justify-center gap-2"
                >
                  {isLoading ? (
                    <div className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  ) : (
                    <Send size={20} />
                  )}
                  Submit Detections
                </button>
              </div>
            </div>
          )}

          {activeTab === 'terminal' && (
            <div className="bg-[#0f172a] border border-slate-700 rounded-xl overflow-hidden shadow-2xl">
              <div className="bg-slate-800 px-4 py-2 border-b border-slate-700 flex items-center gap-2">
                <Terminal size={14} className="text-slate-400" />
                <span className="text-xs font-mono text-slate-400">api-response.json</span>
              </div>
              <div className="p-6 overflow-x-auto">
                {response ? (
                  <pre className="text-sm font-mono text-emerald-400 leading-relaxed">
                    {JSON.stringify(response, null, 2)}
                  </pre>
                ) : (
                  <p className="text-slate-500 italic font-mono text-sm">No data submitted yet.</p>
                )}
              </div>
            </div>
          )}

          {(activeTab !== 'dashboard' && activeTab !== 'input' && activeTab !== 'terminal') && (
            <div className="flex flex-col items-center justify-center py-20 text-slate-500">
               <Box size={48} className="mb-4 opacity-20" />
               <p className="text-lg">Module "{activeTab}" is ready for implementation.</p>
               <p className="text-sm opacity-50">Connection to {activeTab}.mycelium.internal established.</p>
            </div>
          )}
        </div>
      </main>
    </div>
  )
}

function NavItem({ active, onClick, icon, label }: any) {
  return (
    <button 
      onClick={onClick}
      className={`w-full flex items-center gap-3 px-4 py-2.5 rounded-lg text-sm font-medium transition-all ${
        active 
          ? 'bg-blue-600/20 text-blue-400 border border-blue-600/30' 
          : 'text-slate-400 hover:bg-slate-800 hover:text-slate-200'
      }`}
    >
      {icon}
      {label}
    </button>
  )
}

function StatCard({ title, value, change, icon }: any) {
  return (
    <div className="bg-[#1e293b]/50 border border-slate-700/50 rounded-xl p-6 backdrop-blur-sm">
      <div className="flex items-center justify-between mb-4">
        <div className="p-2 bg-[#0f172a]/50 rounded-lg">
          {icon}
        </div>
        <span className={`text-xs font-medium px-2 py-1 rounded-full ${change.startsWith('+') ? 'bg-emerald-500/10 text-emerald-400' : 'bg-slate-500/10 text-slate-400'}`}>
          {change}
        </span>
      </div>
      <p className="text-slate-400 text-sm font-medium">{title}</p>
      <p className="text-2xl font-bold text-slate-100 mt-1">{value}</p>
    </div>
  )
}

function HealthItem({ label, status }: any) {
  return (
    <div className="flex items-center justify-between py-2 border-b border-slate-700/30 last:border-0">
      <span className="text-sm text-slate-400">{label}</span>
      <div className="flex items-center gap-2">
        <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-500">{status}</span>
        <div className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
      </div>
    </div>
  )
}

export default App
