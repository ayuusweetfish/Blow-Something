export const words = [
  { word: { zh: '太阳', en: 'Sun' }, hint: '某个天体' },
  { word: { zh: '月亮/月球', en: 'Moon' }, hint: '某个天体' },
  { word: { zh: '云/云朵', en: 'Cloud/Clouds' }, hint: '某种气象' },
  { word: { zh: '苹果', en: 'Apple' }, hint: '某种水果' },
  { word: { zh: '橙子/橘子/桔子', en: 'Orange/Tangerine/Mandarin' }, hint: '某种水果' },
  { word: { zh: '香蕉', en: 'Banana' }, hint: '某种水果' },
  { word: { zh: '水母', en: 'Jellyfish' }, hint: '某种生物' },
  { word: { zh: '树', en: 'Tree' }, hint: '某类植物' },
  { word: { zh: '大象', en: 'Elephant' }, hint: '某种大型动物' },
  { word: { zh: '蘑菇', en: 'Mushroom' }, hint: '某种生物' },
  { word: { zh: '花生', en: 'Peanut/Peanuts' }, hint: '某种坚果' },
  { word: { zh: '鱼', en: 'Fish' }, hint: '某种动物' },
  { word: { zh: '汽车/轿车', en: 'Car' }, hint: '某种交通工具' },
  { word: { zh: '花/花朵', en: 'Flower' }, hint: '某种植物' },
  { word: { zh: '蝴蝶', en: 'Butterfly' }, hint: '某种动物' },
  { word: { zh: '鸟', en: 'Bird' }, hint: '某种动物' },
  { word: { zh: '冰淇淋/冰激凌/甜筒/蛋筒', en: 'Ice-cream' }, hint: '某种食品' },
  { word: { zh: '帽子/鸭舌帽', en: 'Hat/Cap' }, hint: '某种服饰' },
  { word: { zh: '彩虹', en: 'Rainbow' }, hint: '某种气象' },
  { word: { zh: '灯/吊灯/灯泡/电灯泡/灯珠', en: 'Light/Lamp/Pendant/Lightbulb/Light bulb' }, hint: '某种室内家具' },
  { word: { zh: '柠檬', en: 'Lemon' }, hint: '某种水果' },
  { word: { zh: '草莓', en: 'Strawberry' }, hint: '某种水果' },
  { word: { zh: '樱桃', en: 'Cherry/Cherries' }, hint: '某种水果' },
  { word: { zh: '雪人', en: 'Snowman' }, hint: '某种室外游戏' },
  { word: { zh: '茶壶/水壶/壶', en: 'Teapot' }, hint: '某种日常用品' },
  // 'a,'bs/{/{ word: { /g | 'a,'bs/ = /: /g | 'a,'bs/},/ }, hint: '' },
]

export const wordLookup = Object.fromEntries(words.flatMap((o) => {
  const { word, hint } = o
  return Object.entries(word).flatMap(
    ([lang, wordForLang]) => wordForLang.split('/').map((w) => [ w, { hint, lang, origEntry: o } ])
  )
}))

export const wordBingo = (target, recognized) => {
  const w = wordLookup[target]
  return w && w.origEntry.word[w.lang].split('/').indexOf(recognized) !== -1
}

if (import.meta.main) {
  console.log(wordBingo('Cloud', 'Clouds')) // true
  console.log(wordBingo('Fish', 'Clouds'))  // false
  console.log(wordBingo('Fish', 'Fish'))    // true
  console.log(wordBingo('鱼', 'Fish'))      // false
}
