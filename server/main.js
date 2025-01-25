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
    return serveFile(req, '../release/Game-Name-web' + file)
  }
  if (req.method === 'POST' && url.pathname === '/look') {
    const payload = await req.arrayBuffer()
    try {
      const img = await sharp(payload)
      const meta = await img.metadata()
      if (meta.size > 1048576 || meta.width > 512 || meta.height > 512)
        throw new Error('Image too big')
      const reencode = await img.png().toBuffer()
      const result = await llm.askForRecognition(reencode)
      return new Response(result)
    } catch (e) {
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
