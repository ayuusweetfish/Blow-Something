import * as db from './db.js'
import * as llm from './llm.js'

import { serveFile } from 'jsr:@std/http/file-server'
import sharp from 'npm:sharp@0.33.5'  // Ignore Deno's warning about NPM lifecycle scripts

class ErrorHttpCoded extends Error {
  constructor(status, message = '') {
    super(message)
    this.status = status
  }
}

const extractParams = (payload, keys) => {
  const params = []
  for (let key of keys) {
    let value =
      (payload instanceof FormData || payload instanceof URLSearchParams) ?
        payload.get(key) : payload[key]
    if (value === null || value === undefined)
      throw new ErrorHttpCoded(400, `${key} is not present`)
    params.push(value)
  }
  return params
}

const serveReq = async (req) => {
  const url = new URL(req.url)
  if (req.method === 'GET' && url.pathname.match(/^\/[a-zA-Z0-9_\-.]*$/)) {
    const file = (url.pathname === '/' ? '/index.html' : url.pathname)
    const resp = await serveFile(req, 'Blow-Something-web/' + file)
    resp.headers.set('Cross-Origin-Opener-Policy', 'same-origin')
    resp.headers.set('Cross-Origin-Embedder-Policy', 'require-corp')
    return resp
  }
  if (req.method === 'POST' && url.pathname === '/hi') {
    const payload = await req.arrayBuffer()
    console.log(payload)
    return new Response(new TextDecoder().decode(payload))
  }
  if (req.method === 'POST' && url.pathname === '/look') {
    const payload = await req.arrayBuffer()
    const u8View = new Uint8Array(payload)
    const p = u8View.indexOf('/'.charCodeAt(0))
    if (p === -1) throw new ErrorHttpCoded(400, 'Request does not contain target word')
    try {
      const targetWord = new TextDecoder().decode(u8View.slice(0, p))
      const img = await sharp(payload.slice(p + 1))
      const meta = await img.metadata()
      if (meta.size > 1048576 || meta.width > 512 || meta.height > 512)
        throw new Error('Image too big')
      const composite = await img.flatten({ background: '#101010' })
      const reencode = await composite.png().toBuffer()
      const result = await llm.askForRecognition(reencode)
      await db.logGame(targetWord, reencode, result)
      return new Response(result)
    } catch (e) {
      console.log(e.message, e.stack)
      throw new ErrorHttpCoded(400, e.message)
    }
  }
  return new Response('Void space, please return', { status: 404 })
}

const serveReqWrapped = async (req) => {
  try {
    return await serveReq(req)
  } catch (e) {
    if (e instanceof ErrorHttpCoded) {
      return new Response(e.message, { status: e.status })
    } else {
      console.log(e)
      return new Response('Internal server error: ' +
        (e instanceof Error) ? e.message : e.toString(), { status: 500 })
    }
  }
}

const serverPort = +Deno.env.get('SERVE_PORT') || 25126
const server = Deno.serve({ port: serverPort }, serveReqWrapped)
