import { useEffect, useState } from 'react'
import { type Address, type Hex } from 'viem'
import { makeCommitment, saltFromLabel } from './commitment'

type Deployment = {
  network: string
  chainId: number
  status: 'live' | 'placeholder'
  contracts: Record<string, string | null>
  explorerBaseUrl: string
  note: string
}

const WAD = 10n ** 18n
const USDC = 10n ** 6n
const ALICE = '0x00000000000000000000000000000000000A11cE' as Address
const BOB = '0x0000000000000000000000000000000000000B0b' as Address
const aliceHash = makeCommitment({ batchId: 1n, owner: ALICE, zeroForOne: true, amountIn: 10n * WAD, minAmountOut: 19_900n * USDC, recipient: ALICE, nonce: 1n }, saltFromLabel('alice-demo-salt'))
const bobHash = makeCommitment({ batchId: 1n, owner: BOB, zeroForOne: false, amountIn: 14_000n * USDC, minAmountOut: 7n * WAD, recipient: BOB, nonce: 1n }, saltFromLabel('bob-demo-salt'))

const phases = [
  ['01', 'Commit', 'Sealed intents enter the batch'],
  ['02', 'Reveal', 'Orders become verifiable'],
  ['03', 'React', 'Authenticated callback starts settlement'],
  ['04', 'Net', 'Compatible flow crosses once'],
  ['05', 'Claim', 'Outputs become pull-based'],
]

const trace = [
  ['12:00:00', 'BatchOpened', 'epoch 42 · closeAt 12:02'],
  ['12:00:18', 'OrderCommitted', 'alice · binding hash stored'],
  ['12:00:41', 'OrderCommitted', 'bob · binding hash stored'],
  ['12:02:09', 'OrderRevealed', '2 / 2 commitments valid'],
  ['12:02:12', 'SettlementRequested', 'Lasna callback requested'],
  ['12:02:13', 'InternalFlowMatched', '7 WETH ↔ 14,000 USDC'],
  ['12:02:15', 'ResidualValidated', '3 WETH · nonce consumed'],
  ['12:02:19', 'BatchSettled', 'Alice + Bob claimable'],
]

function shortHash(hash: Hex) {
  return `${hash.slice(0, 10)}…${hash.slice(-8)}`
}

function DeploymentPanel() {
  const [deployment, setDeployment] = useState<Deployment | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let active = true
    fetch('/deployments/testnet.json')
      .then((response) => {
        if (!response.ok) throw new Error('Deployment manifest unavailable')
        return response.json() as Promise<Deployment>
      })
      .then((data) => active && setDeployment(data))
      .catch(() => active && setFailed(true))
    return () => { active = false }
  }, [])

  return (
    <section className="deployment section-rule" id="deployment">
      <div>
        <p className="eyebrow">Testnet manifest</p>
        <h2>Deployment evidence,<br />not deployment theater.</h2>
      </div>
      <div className="deploy-card">
        {!deployment && !failed && <p className="loading"><span />Loading deployment manifest…</p>}
        {failed && <p className="error">Manifest could not be loaded.</p>}
        {deployment && (
          <>
            <div className="deploy-head">
              <div><span className="muted">Target network</span><strong>{deployment.network}</strong></div>
              <span className={`status ${deployment.status}`}>{deployment.status === 'live' ? 'Live' : 'Not deployed'}</span>
            </div>
            <div className="address-list">
              {Object.entries(deployment.contracts).map(([name, address]) => (
                <div className="address-row" key={name}>
                  <span>{name.replace(/([A-Z])/g, ' $1')}</span>
                  {address ? <a href={`${deployment.explorerBaseUrl}${address}`}>{shortHash(address as Hex)}</a> : <code>address pending</code>}
                </div>
              ))}
            </div>
            <p className="manifest-note">Chain ID {deployment.chainId}. {deployment.note}</p>
          </>
        )}
      </div>
    </section>
  )
}

export function App() {
  return (
    <div className="site-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="CommitBatch home"><span className="brand-mark">CB</span>CommitBatch</a>
        <nav aria-label="Primary navigation">
          <a href="#mechanism">Mechanism</a>
          <a href="#evidence">Evidence</a>
          <a href="#deployment">Testnet</a>
        </nav>
        <span className="demo-chip"><i />Static protocol demo</span>
      </header>

      <main id="top">
        <section className="hero">
          <div className="hero-copy">
            <p className="eyebrow">Commit-bound flow · atomic settlement</p>
            <h1>Cross the overlap.<br /><em>Route only the rest.</em></h1>
            <p className="lede">CommitBatch binds order terms before reveal, nets compatible flow at a shared clearing price, and sends only the unmatched residual through an authorized execution hook.</p>
            <div className="hero-actions">
              <a className="button primary" href="#mechanism">Trace batch 42 <span>↓</span></a>
              <a className="button secondary" href="#evidence">Inspect guarantees</a>
            </div>
          </div>
          <div className="hero-figure" aria-label="Batch 42 settlement summary">
            <div className="figure-grid" />
            <p className="figure-label">BATCH / 042</p>
            <div className="orbit orbit-a"><span>A</span></div>
            <div className="orbit orbit-b"><span>B</span></div>
            <div className="core">
              <strong>7</strong><span>WETH<br />NETTED</span>
            </div>
            <div className="residual-tag"><span />3 WETH residual</div>
            <p className="price-tag">CLEARING PRICE<br /><strong>2,000 USDC / ETH</strong></p>
          </div>
        </section>

        <section className="scenario-strip" aria-label="Fixed scenario">
          <div><span>Seller A</span><strong>Alice</strong><b>10 WETH</b></div>
          <div className="operator">×</div>
          <div><span>Seller B</span><strong>Bob</strong><b>14,000 USDC</b></div>
          <div className="operator">=</div>
          <div><span>Matched internally</span><strong>7 WETH</strong><b>14,000 USDC</b></div>
          <div><span>Route externally</span><strong className="coral">3 WETH</strong><b>residual only</b></div>
        </section>

        <section className="timeline-wrap section-rule" id="mechanism">
          <div className="section-heading">
            <div><p className="eyebrow">One bounded lifecycle</p><h2>From sealed intent<br />to funded claim.</h2></div>
            <p>Each phase advances the batch state. No external route can execute before valid reveals are netted.</p>
          </div>
          <ol className="timeline">
            {phases.map(([number, name, detail], index) => (
              <li key={number} className={index === 2 ? 'active' : ''}>
                <span className="phase-number">{number}</span>
                <i />
                <strong>{name}</strong>
                <small>{detail}</small>
              </li>
            ))}
          </ol>
        </section>

        <section className="commits section-rule">
          <div className="section-heading compact">
            <div><p className="eyebrow">Commit / reveal</p><h2>Orders enter sealed.</h2></div>
            <p>Hashes shown below are deterministic demo fixtures, computed in-browser with viem.</p>
          </div>
          <div className="commit-grid">
            <article className="commit-card alice">
              <div className="card-top"><span className="avatar">A</span><span className="verified">✓ REVEALED</span></div>
              <p className="eyebrow">Alice · sell intent</p><h3>10 <small>WETH</small></h3>
              <div className="commit-meta"><span>Limit</span><strong>2,000 USDC / ETH</strong><span>Commitment</span><code title={aliceHash}>{shortHash(aliceHash)}</code></div>
              <div className="hash-line"><span style={{ width: '72%' }} /></div>
            </article>
            <article className="commit-card bob">
              <div className="card-top"><span className="avatar">B</span><span className="verified">✓ REVEALED</span></div>
              <p className="eyebrow">Bob · sell intent</p><h3>14,000 <small>USDC</small></h3>
              <div className="commit-meta"><span>Limit</span><strong>2,000 USDC / ETH</strong><span>Commitment</span><code title={bobHash}>{shortHash(bobHash)}</code></div>
              <div className="hash-line"><span style={{ width: '54%' }} /></div>
            </article>
          </div>
          <p className="privacy-note"><span>BINDING, NOT PRIVATE</span> The hash prevents either trader changing terms after commitment. Token transfers, deposit amounts, senders, calldata and timing remain public; CommitBatch does not claim transaction privacy.</p>
        </section>

        <section className="netting section-rule">
          <div className="netting-copy">
            <p className="eyebrow">Deterministic netting</p>
            <h2>One overlap.<br /><span>Zero redundant flow.</span></h2>
            <p>Bob's 14,000 USDC buys exactly 7 WETH at the agreed 2,000 price. That crossing settles inside the batch. Alice's remaining 3 WETH becomes the only routable amount.</p>
            <dl><div><dt>Gross inputs</dt><dd>10 WETH + 14k USDC</dd></div><div><dt>Internal transfer</dt><dd>7 WETH ↔ 14k USDC</dd></div><div><dt>External exposure</dt><dd className="coral">3 WETH</dd></div></dl>
          </div>
          <div className="flow-map" aria-label="Netting flow diagram">
            <div className="flow-party party-a"><span>A</span><strong>Alice</strong><small>10 WETH in</small></div>
            <div className="flow-party party-b"><span>B</span><strong>Bob</strong><small>14k USDC in</small></div>
            <svg viewBox="0 0 600 340" role="img" aria-label="Alice and Bob flow into a seven WETH match with a three WETH residual">
              <defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" /></marker></defs>
              <path className="path alice-path" d="M105 95 C220 95 205 170 300 170" />
              <path className="path bob-path" d="M495 95 C380 95 395 170 300 170" />
              <path className="path residual-path" markerEnd="url(#arrow)" d="M300 193 C300 245 400 248 455 290" />
            </svg>
            <div className="match-node"><strong>7</strong><span>WETH<br />MATCH</span></div>
            <div className="route-node"><span>Authorized route</span><strong>3 WETH</strong></div>
          </div>
        </section>

        <section className="reactive section-rule">
          <div className="trace-panel">
            <div className="terminal-head"><span><i /><i /><i /></span><code>reactive://batch/42/trace</code><b>8 events</b></div>
            <div className="trace-body">
              {trace.map(([time, event, detail], index) => <div className="trace-row" key={event}><span>{time}</span><i className={index > 4 ? 'warm' : ''} /><strong>{event}</strong><code>{detail}</code></div>)}
            </div>
          </div>
          <div className="reactive-copy">
            <p className="eyebrow">Reactive trace</p><h2>Observe first.<br />Authorize second.</h2>
            <p>Reactive responds to <code>SettlementRequested</code> and performs the authenticated state transition. Settlement then creates a one-time authorization scoped to one batch, direction, exact amount, nonce and price bound.</p>
            <div className="hook-ticket">
              <div><span>RESIDUAL HOOK / AUTHORIZATION</span><b>VALID FOR BATCH 42</b></div>
              <dl><div><dt>Asset</dt><dd>WETH</dd></div><div><dt>Max input</dt><dd>3.000</dd></div><div><dt>Min output</dt><dd>policy-bound</dd></div><div><dt>Replay</dt><dd>consumed nonce</dd></div></dl>
              <p>Scope hash <code>0x42c7…91ea</code></p>
            </div>
          </div>
        </section>

        <section className="claims section-rule">
          <div className="section-heading compact"><div><p className="eyebrow">Pull-based settlement</p><h2>Fund, then claim.</h2></div><p>Claims isolate user withdrawals from batch execution. The figures are scenario outcomes, not connected wallet balances.</p></div>
          <div className="claim-grid">
            <article><span className="avatar">A</span><div><small>ALICE CAN CLAIM</small><strong>14,000 + <em>v4 USDC</em></strong><p>matched output plus residual execution output</p></div><button disabled>Demo only</button></article>
            <article><span className="avatar">B</span><div><small>BOB CAN CLAIM</small><strong>7 <em>WETH</em></strong><p>at 2,000 USDC / ETH</p></div><button disabled>Demo only</button></article>
            <article className="pending"><span className="route-icon">↗</span><div><small>ALICE RESIDUAL</small><strong>3 <em>WETH</em></strong><p>authorized for external execution</p></div><span className="pending-chip">HOOK</span></article>
          </div>
        </section>

        <section className="comparison section-rule">
          <div className="comparison-head"><p className="eyebrow">Why batch?</p><h2>Sequential execution leaks<br />what netting removes.</h2></div>
          <div className="compare-table">
            <div className="compare-column old"><header><span>01</span><div><strong>Sequential swaps</strong><small>Two independent routes</small></div></header><div className="meter"><span style={{ width: '100%' }} /></div><dl><div><dt>Externally routed</dt><dd>17 WETH-equivalent*</dd></div><div><dt>AMM interactions</dt><dd>2</dd></div><div><dt>Execution pricing</dt><dd>Order-dependent</dd></div><div><dt>Internal matching</dt><dd>0%</dd></div></dl></div>
            <div className="versus">VS</div>
            <div className="compare-column new"><header><span>02</span><div><strong>CommitBatch</strong><small>Net overlap, route residual</small></div></header><div className="meter"><span style={{ width: '18%' }} /></div><dl><div><dt>Externally routed</dt><dd>3 WETH-equivalent*</dd></div><div><dt>AMM interactions</dt><dd>1 bounded swap</dd></div><div><dt>Execution pricing</dt><dd>Uniform for matched flow</dd></div><div><dt>Internal matching</dt><dd>82.35% normalized</dd></div></dl></div>
          </div>
          <p className="footnote">* Inputs normalized at 2,000 USDC/ETH. The comparison states reserves, fee and execution assumptions separately; it does not claim the residual is MEV-free.</p>
        </section>

        <section className="evidence section-rule" id="evidence">
          <div className="evidence-intro"><p className="eyebrow">Security evidence</p><h2>Claims require<br />proof, not prose.</h2><p>This demo maps each guarantee to a concrete invariant or artifact expected from the protocol implementation.</p></div>
          <div className="evidence-grid">
            <article><span>INV-01</span><h3>Conservation</h3><p>Claimable outputs plus residual never exceed funded batch inputs.</p><code>Σ out ≤ Σ escrowed</code></article>
            <article><span>INV-02</span><h3>Commit binding</h3><p>Reveal fields and salt must reproduce the stored commitment exactly.</p><code>H(reveal) == commit</code></article>
            <article><span>INV-03</span><h3>Scoped authority</h3><p>The hook cannot spend another token, epoch, nonce, or excess amount.</p><code>spent ≤ residual</code></article>
            <article><span>INV-04</span><h3>Single settlement</h3><p>State advances before interaction; claims and authorizations are replay-safe.</p><code>status: OPEN → FINAL</code></article>
          </div>
        </section>

        <DeploymentPanel />
      </main>

      <footer><a className="brand" href="#top"><span className="brand-mark">CB</span>CommitBatch</a><p>Fixed-scenario interface demonstration.<br />No wallet connection. No live transactions.</p><span>COMMIT · NET · REACT · CLAIM</span></footer>
    </div>
  )
}
