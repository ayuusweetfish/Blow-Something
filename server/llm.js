import { logNetwork } from './db.js'
import { encodeBase64 } from 'jsr:@std/encoding/base64'

const loggedFetchJSON = async (url, options) => {
  const t0 = Date.now()
  const resp = await fetch(url, options)
  const respText = await resp.text()
  await logNetwork(url, options.body, respText, Date.now() - t0)
  console.log(url, respText)
  return JSON.parse(respText)
}

const getKey = (name) => () => Deno.env.get(name) || prompt(`API key (${name}):`)

const requestLLM_OpenAI = (endpoint, model, temperature, maxTokens, keyFn) => async (messages, isStreaming) => {
  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + keyFn(),
    },
    body: JSON.stringify({
      model: model,
      messages,
      temperature: temperature,
      max_tokens: maxTokens,
      enable_thinking: false, // Defaults to true for Qwen3.5 > <
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

const requestLLM_Google = (model, temperature, keyFn) => async (messages) => {
  // Ref: https://ai.google.dev/api/generate-content#v1beta.models.generateContent
  const resp = await loggedFetchJSON(
    'https://generativelanguage.googleapis.com/v1beta/models/' + model + ':generateContent?key=' + keyFn(),
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        generationConfig: {
          temperature: temperature,
        },
        systemInstruction: { parts: [{ text:
          messages.filter(({ role }) => role === 'system')
                  .map(({ content }) => content).join('\n'),
        }] },
        contents:
          messages.filter(({ role }) => role === 'user')
                  .map(({ content }) => ({
                    role: 'user',
                    parts: content, // (Parts[]) content
                  })),
      }),
    }
  )

  // Extract text
  const { candidates } = resp
  const [ candidate ] = candidates
  const { content } = candidate
  const { parts } = content
  if (!(parts instanceof Array)) throw new Error('Incorrect schema!')
  const text = parts.map(({ text }) => text || '').join('')

  return [resp, text]
}

const requestLLM_GLM4vPlus = requestLLM_OpenAI(
  'https://open.bigmodel.cn/api/paas/v4/chat/completions', 'glm-4v-plus-0111', 1.0, undefined,
  getKey('API_KEY_ZHIPU'),
)
const requestLLM_GLM4vFlash = requestLLM_OpenAI(
  'https://open.bigmodel.cn/api/paas/v4/chat/completions', 'glm-4v-flash', 1.0, undefined,
  getKey('API_KEY_ZHIPU'),
)
const requestLLM_Gemini15Flash = requestLLM_Google(
  'gemini-1.5-flash', 1.0,
  getKey('API_KEY_GOOGLE'),
)
const requestLLM_Gemini20FlashExp = requestLLM_Google(
  'gemini-2.0-flash-exp', 1.0,
  getKey('API_KEY_GOOGLE'),
)

// https://bailian.console.aliyun.com/cn-beijing/?spm=a2ty02.33053938.resourceCenter.1.193c74a1mW6rl9&tab=api#/api/?type=model&url=3016807
const requestLLM_Qwen35Plus = requestLLM_OpenAI(
  'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
  'qwen3.5-plus', 0.7 /* Default */, 512,
  getKey('API_KEY_ALIYUN'),
)

const retry = (fn, attempts, errorMsgPrefix) => async (...args) => {
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn(...args)
    } catch (e) {
      console.log(`${errorMsgPrefix}:`, e)
      if (i === attempts - 1) throw e
      continue
    }
  }
}

// Application-specific routines

const hint = {
  '太阳': '某个天体',
  '月亮': '某个天体',
  '云': '某种气象',
  '苹果': '某种红色水果',
  '橙子': '某种橙色水果',
  '香蕉': '某种黄色水果',
  '水母': '某种海洋生物',
  '树': '某类植物',
  '大象': '某种大型动物',
  '蘑菇': '某种腐生生物',
  '花生': '某种坚果',
  '鱼': '某种水生生物',
  '汽车': '某种交通工具',
}

// For logging and debugging
export const getHint = (targetWord, prevAttempts) => {
  if (prevAttempts.length === 0) return ''
  return prevAttempts.map((s) => `${s}×`).join(' ') +
    (prevAttempts.length >= 2 ? ` ${hint[targetWord]}?` : '')
}

const _askForRecognition = async (image, targetWord, prevAttempts) => {
  const prev = (prevAttempts.length > 0 ? `已知错误答案：${prevAttempts.join('、')}。` : '')
  const ref = (prevAttempts.length >= 2 ? `小提示：你是否觉得它像${hint[targetWord]}？` : '')
  const userText = `这张图描绘了一种人们所熟知的事物（植物、动物、自然物体或日常生活中常见的物品）。它是尝试用细绳绘制出的图案外形，所以轮廓可能不准确。你可以尽力猜猜原本想画的是什么吗？请记住猜测的是常见事物，而绘画形状可能歪斜、不准确，请你猜测原始意图。请将你的猜测以**加粗**输出，仅给出核心词语（名词）即可。${prev}${ref}`

  // XXX: `encodeBase64` (@std/encoding@1.0.10) drains `Buffer` but not `Uint8Array`???
  // Clone for now to work around
  const imageCloned = new Uint8Array(image)
  image = imageCloned

if (0) {
  const [_, text] = await requestLLM_GLM4vPlus([
    { role: 'user', content: [
      {
        type: 'image_url',
        image_url: {
          url: encodeBase64(image),
        },
      }, {
        type: 'text',
        text: userText,
      },
    ] },
  ])
}

if (0) {
  const [_, text] = await requestLLM_Gemini15Flash([
    { role: 'user', content: [
      { inlineData: { mimeType: 'image/png', data: encodeBase64(image) } },
      { text: userText },
    ] },
  ])
}

  const [_, text] = await requestLLM_Qwen35Plus([
    { role: 'user', content: [
      {
        type: 'text',
        text: userText,
      }, {
        type: 'image_url',
        image_url: {
          url: 'data:image/png;base64,' + encodeBase64(image),
        },
      },
    ] },
  ])

  const match = text.match(/\*\*([^*]+)\*\*[^*]*$/)
  if (!match) {
    if (text.length <= 8) return text
    throw new Error('Malformed response from AI')
  }
  return match[1]
}
export const askForRecognition = retry(_askForRecognition, 3, 'Cannot ask for recognition')

// ======== Test run ======== //
if (import.meta.main) {
  console.log(await askForRecognition(await Deno.readFile('banana-1.png'), '香蕉', ['腰果']))
}
