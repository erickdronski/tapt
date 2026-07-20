// Decides whether an Open Food Facts product is beer, using OFF's
// language-independent category taxonomy instead of English substrings.
//
// OFF returns `categories_tags` as a fully expanded hierarchy of `lang:slug`
// ids. Categories that exist in the OFF taxonomy are normalised to their
// canonical English id in every language (a French lager still carries
// `en:beers`), while contributor categories that are not in the taxonomy keep
// the entry language: `pl:piwa`, `de:helles-vollbier`, `it:birra-artigianale`.
// Looking for the English word "beer" therefore drops real foreign beers, and
// accepting any tag that contains "beer" would let root beer, ginger beer,
// beer bread, beer cheese and beer batter in.
//
// Must stay in sync with app/Tapt/Core/OFFBeerTaxonomy.swift.

/** Slug fragments that name a soda or a food, never a beer. Any language. */
const EXCLUDED_FRAGMENTS = [
  "root-beer", "rootbeer", "ginger-beer", "gingerbeer",
  "birch-beer", "spruce-beer", "sarsaparilla",
  "beer-bread", "beer-cheese", "beer-batter",
  "wurzelbier", "ingwerbier", "gemberbier", "racinette",
  "biere-de-racine", "cerveza-de-raiz", "birra-di-radice",
];

/** Canonical beer ids whose last word is not "beer"/"beers". */
const BEER_IDS = new Set([
  "en:beers-and-ciders", "en:ales", "en:lagers", "en:stouts",
  "en:porters", "en:pilsners", "en:india-pale-ales", "en:pale-ales",
  "en:witbier", "en:weissbier", "en:shandy",
]);

/** First word of an untranslated tag, one language each, diacritics folded. */
const BEER_WORDS = new Set([
  "bier", "biere", "bieres", "biers", "bieren",
  "birra", "birre",
  "cerveza", "cervezas", "cervesa", "cerveses",
  "cerveja", "cervejas",
  "piwo", "piwa",
  "pivo", "piva",
  "ol", "øl", "olut", "oluet", "olutta", "bjor",
  "sor", "sorok",
  "bere", "beri",
  "bira", "biralar",
  "alus", "olu",
  "bir",
  "garagardo", "garagardoa",
  "пиво", "пива", "бира",
  "μπιρα", "μπιρες",
  "ビール", "啤酒", "맥주",
]);

/** Ids that prove the product sits in OFF's alcoholic-beverage hierarchy. */
const ALCOHOLIC_IDS = new Set([
  "en:alcoholic-beverages", "en:alcoholic-drinks", "en:beers-and-ciders",
]);

/** Alcohol-free beer is still beer, and carries no alcohol nutriment. */
const ALCOHOL_FREE_BEER_IDS = new Set([
  "en:non-alcoholic-beers", "en:non-alcoholic-beer",
  "en:alcohol-free-beers", "en:low-alcohol-beers",
  "en:beers-without-alcohol",
]);

/** Words that turn a beer word into something that is not beer. */
const NON_BEER_MODIFIERS = new Set([
  "racine", "racines", "racinette", "raiz", "radice", "wurzel", "wortel",
  "jengibre", "gengibre", "gingembre", "ingwer", "zenzero", "gember",
  "bouleau", "birke", "abedul", "betulla", "epinette", "fichte",
  "brot", "brood", "pane", "chleb", "kase", "queso", "formaggio", "kaas",
]);

interface Tag {
  id: string;
  language: string;
  slug: string;
  words: string[];
}

function parseTag(raw: unknown): Tag | null {
  if (typeof raw !== "string") return null;
  const folded = raw
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
  if (!folded) return null;

  const colon = folded.indexOf(":");
  // API v2 always prefixes; bare values are English.
  const language = colon >= 0 ? folded.slice(0, colon) : "en";
  const slug = (colon >= 0 ? folded.slice(colon + 1) : folded)
    .replace(/[_\s]+/g, "-");
  if (!slug) return null;

  return {
    id: `${language}:${slug}`,
    language,
    slug,
    words: slug.split("-").filter(Boolean),
  };
}

/**
 * @param categoryTags OFF `categories_tags`, the expanded `lang:slug` hierarchy.
 * @param alcoholByVolume OFF `nutriments.alcohol_100g`, when present.
 */
export function isBeerCategory(
  categoryTags: unknown,
  alcoholByVolume?: number | null,
): boolean {
  if (!Array.isArray(categoryTags)) return false;
  const tags = categoryTags
    .map(parseTag)
    .filter((tag): tag is Tag => tag !== null);
  if (tags.length === 0) return false;

  // 1. Root beer, ginger beer, beer bread and friends never qualify.
  if (tags.some((tag) => EXCLUDED_FRAGMENTS.some((f) => tag.slug.includes(f)))) {
    return false;
  }

  // 2. Canonical English taxonomy id, emitted for every language OFF knows.
  const hasCanonicalBeer = tags.some((tag) => {
    if (tag.language !== "en") return false;
    if (BEER_IDS.has(tag.id)) return true;
    const last = tag.words[tag.words.length - 1];
    return last === "beer" || last === "beers";
  });
  if (hasCanonicalBeer) return true;

  // 3. Untranslated contributor category, corroborated by an alcohol signal.
  const hasLocalisedBeer = tags.some((tag) =>
    tag.language !== "en" &&
    BEER_WORDS.has(tag.words[0] ?? "") &&
    !tag.words.some((word) => NON_BEER_MODIFIERS.has(word))
  );
  if (!hasLocalisedBeer) return false;

  const alcoholFreeBeer = tags.some((tag) => ALCOHOL_FREE_BEER_IDS.has(tag.id));
  const alcoholic = tags.some((tag) => ALCOHOLIC_IDS.has(tag.id)) ||
    (typeof alcoholByVolume === "number" && alcoholByVolume >= 0.05);
  return alcoholic || alcoholFreeBeer;
}
