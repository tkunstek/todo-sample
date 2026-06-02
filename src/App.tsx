import { useEffect, useState } from 'react'
import { readListsCount } from './services/rlsSmokeService'

export default function App() {
  const [result, setResult] = useState('loading…')
  useEffect(() => {
    readListsCount().then((r) =>
      setResult(r.error ? `error: ${r.error}` : `rows: ${r.rows}`),
    )
  }, [])
  return <pre>anonymous read of lists → {result}</pre>
}
