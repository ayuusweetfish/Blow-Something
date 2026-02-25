export const words = [
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

export const wordLookup = Object.fromEntries(words.flatMap((o) => {
  const { word, hint } = o
  return Object.entries(word).flatMap(
    ([lang, wordForLang]) => wordForLang.split('/').map((w) => [ w, { hint, lang, origEntry: o } ])
  )
}))

export const wordBingo = (target, recognized) => {
  const w = wordLookup[target]
  return w.origEntry.word[w.lang].split('/').indexOf(recognized) !== -1
}

if (import.meta.main) {
  console.log(wordBingo('Cloud', 'Clouds')) // true
  console.log(wordBingo('Fish', 'Clouds'))  // false
  console.log(wordBingo('Fish', 'Fish'))    // true
  console.log(wordBingo('鱼', 'Fish'))      // false
}
