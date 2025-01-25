import { logNetwork } from './db.js'
import { encodeBase64 } from 'jsr:@std/encoding/base64'

const loggedFetchJSON = async (url, options) => {
  const t0 = Date.now()
  const req = await fetch(url, options)
  const respText = await req.text()
  await logNetwork(url, options.body, respText, Date.now() - t0)
  console.log(url, respText)
  return JSON.parse(respText)
}

const requestLLM_OpenAI = (endpoint, model, temperature, key) => async (messages, isStreaming) => {
  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + key,
    },
    body: JSON.stringify({
      model: model,
      messages,
      // max_tokens: 8000,  // GLM-4V does not accept `max_tokens`
      temperature: temperature,
      stream: (isStreaming ? true : undefined),
    }),
  }

  if (isStreaming) {
    const t0 = Date.now()
    const es = createEventSource({ url: endpoint, ...options })
    let buffer = ''

    return {
      [Symbol.asyncIterator]: async function* () {
        const bufferCombined = []

        for await (const chunk of es) {
          bufferCombined.push(chunk.data)
          if (chunk.data === '[DONE]') break
          try {
            const payload = JSON.parse(chunk.data)
            const s = payload.choices[0].delta.content
            // Ensure horizontal rules are not broken
            // There are better ways to return other parts early,
            // but benefit is negligible latency at one point in time. So ignore that.
            if (s.match(/-[^\S\r\n]*$/)) buffer += s
            else {
              yield buffer + s
              buffer = ''
            }
          } catch (e) {
            break
          }
        }

        es.close()
        if (buffer) yield buffer
        await logNetwork(endpoint, options.body, bufferCombined.join('\n'), Date.now() - t0)
      }
    }

  } else {
    const resp = await loggedFetchJSON(endpoint, options)
    // Extract text
    if (!(resp.choices instanceof Array) ||
        resp.choices.length !== 1 ||
        typeof resp.choices[0] !== 'object' ||
        typeof resp.choices[0].message !== 'object' ||
        resp.choices[0].message.role !== 'assistant' ||
        typeof resp.choices[0].message.content !== 'string')
      throw new Error('Incorrect schema from AI')
    const text = resp.choices[0].message.content
    return [resp, text]
  }
}

const requestLLM_GLM4vPlus = requestLLM_OpenAI(
  'https://open.bigmodel.cn/api/paas/v4/chat/completions', 'glm-4v-plus-0111', 1.0,
  Deno.env.get('API_KEY_ZHIPU') || prompt('API key (Zhipu):')
)
const requestLLM_GLM4vFlash = requestLLM_OpenAI(
  'https://open.bigmodel.cn/api/paas/v4/chat/completions', 'glm-4v-flash', 1.0,
  Deno.env.get('API_KEY_ZHIPU') || prompt('API key (Zhipu):')
)

const retry = (fn, attempts, errorMsgPrefix) => async (...args) => {
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn(...args)
    } catch (e) {
      console.log(`${errorMsgPrefix}: ${e}`)
      if (i === attempts - 1) throw e
      continue
    }
  }
}

// Application-specific routines

const _askForRecognition = async (image) => {
  const [_, text] = await requestLLM_GLM4vPlus([
    { role: 'user', content: [
      {
        type: 'image_url',
        image_url: {
          url: encodeBase64(image),
        },
      }, {
        type: 'text',
        text: '这张图描绘了一种人们所熟知的事物。它是人类尝试用水滴绘制出的图案外形，所以可能不准确。你可以尽力猜猜原本想画的是什么吗？只需给出你所猜的词即可。',
      },
    ] },
  ])
  return text
}
export const askForRecognition = retry(_askForRecognition, 3, 'Cannot ask for recognition')

// ======== Test run ======== //
if (import.meta.main) {
  console.log(await askForRecognition(await Deno.readFile('peach-1.png')))
}
