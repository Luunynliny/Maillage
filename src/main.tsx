import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App.tsx'
import { VaultProvider } from './vault/store.tsx'
import './design/theme.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <VaultProvider>
      <App />
    </VaultProvider>
  </StrictMode>,
)
