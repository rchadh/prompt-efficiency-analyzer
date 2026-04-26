import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import PromptScorer from './PromptAnalyzer.jsx'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <PromptScorer />
  </StrictMode>,
)
