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

const words = [
  { word: { zh: '太阳', en: 'Sun' }, hint: '某个天体' },
  { word: { zh: '月亮/月球', en: 'Moon' }, hint: '某个天体' },
  { word: { zh: '云/云朵', en: 'Cloud/Clouds' }, hint: '某种气象' },
  { word: { zh: '苹果', en: 'Apple' }, hint: '某种水果' },
  { word: { zh: '橙子/橘子/桔子', en: 'Orange/Tangerine/Mandarin' }, hint: '某种水果' },
  { word: { zh: '香蕉', en: 'Banana' }, hint: '某种水果' },
  { word: { zh: '水母', en: 'Jellyfish' }, hint: '某种水生生物' },
  { word: { zh: '树', en: 'Tree' }, hint: '某类植物' },
  { word: { zh: '大象', en: 'Elephant' }, hint: '某种大型动物' },
  { word: { zh: '蘑菇', en: 'Mushroom' }, hint: '某种生物' },
  { word: { zh: '花生', en: 'Peanut/Peanuts' }, hint: '某种坚果' },
  { word: { zh: '鱼', en: 'Fish' }, hint: '某种水生动物' },
  { word: { zh: '汽车', en: 'Car' }, hint: '某种交通工具' },
]
const wordLookup = Object.fromEntries(words.flatMap((o) => {
  const { word, hint } = o
  return Object.entries(word).flatMap(
    ([lang, wordForLang]) => wordForLang.split('/').map((w) => [ w, { hint, lang, origEntry: o } ])
  )
}))

// For logging and debugging
export const getHint = (targetWord, prevAttempts) => {
  if (prevAttempts.length === 0) return ''
  return prevAttempts.map((s) => `${s}×`).join(' ') +
    (prevAttempts.length >= 2 ? ` ${wordLookup[targetWord].hint}?` : '')
}

const _askForRecognition = async (image, targetWord, prevAttempts) => {
  const lang = wordLookup[targetWord].lang

  const prev = (prevAttempts.length > 0 ? `已知错误答案：${prevAttempts.join('、')}。` : '')
  const ref = (prevAttempts.length >= 2 ? `小提示：你是否觉得它像${wordLookup[targetWord].hint}？` : '')
  const langReq = (wordLookup[targetWord].lang !== 'zh' ? `请用**英语单词**回答。` : '')
  const userText = `这张图描绘了一种人们所熟知的事物（植物、动物、自然物体或日常生活中常见的物品）。它是尝试用细绳绘制出的图案外形，所以轮廓可能不准确。你可以尽力猜猜原本想画的是什么吗？请记住猜测的是常见事物，而绘画形状可能歪斜、不准确，请你猜测原始意图。请将你的猜测以**加粗**输出，仅给出核心词语（名词）即可。${langReq}${prev}${ref}`

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
  let responseWord = match[1]

  if (lang === 'en')
    responseWord = responseWord.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase())

  return responseWord
}
export const askForRecognition = retry(_askForRecognition, 3, 'Cannot ask for recognition')

// ======== Test run ======== //
if (import.meta.main) {
  console.log(await askForRecognition(await Deno.readFile('banana-1.png'), '香蕉', ['腰果']))
}
