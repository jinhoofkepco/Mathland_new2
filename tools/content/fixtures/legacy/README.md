# Pinned SeoaQuiz compatibility fixtures

These five CSV files are byte-for-byte development/test fixtures copied from
[`jinhoofkepco/SeoaQuiz`](https://github.com/jinhoofkepco/SeoaQuiz) at commit
`08b9e7589a335f0c5674cfac6743132f8c4870f2` (tree
`4a9311409399983b7da4f6f6a5fe102c3a6be8fe`). They were retrieved and verified
through the GitHub API on 2026-07-21.

| Fixture | Original path | Git blob | SHA-256 |
|---|---|---|---|
| `quiz_game_11.csv` | `app/src/main/res/raw/quiz_game_11.csv` | `f27c926197b8d9f4b866cdcbb62c8b0ee2acda6a` | `2bc0680a92758d1038854574f7f1f0dafe8ea17f5504990bd91e39b54de08329` |
| `quiz_game_7.csv` | `app/src/main/res/raw/quiz_game_7.csv` | `876b1d423b8628ba6f4866857a3e49f18586c1ca` | `332afe72a2ede14f8cbc7e6659ca5028bafac368567b9550afb2a884041f1308` |
| `quiz_game_4.csv` | `app/src/main/res/raw/quiz_game_4.csv` | `a8c698ff675c0058cc8b2e986ad331d2c7503eb5` | `c6988f44a219ae324fc7d532ab8aafe1d360ee834888e945bfec07b2a4cbdc8c` |
| `quiz_game_9.csv` | `app/src/main/res/raw/quiz_game_9.csv` | `4948ef661740652873390b016ab70961d5bb2910` | `d5e83eca772cfd3c6657702e3432fb7e807e46b29ddc198b201988938671bdc4` |
| `quiz_game_8_1.csv` | `app/src/main/res/raw/quiz_game_8_1.csv` | `be9563f785f33588cf7e40f78058dc5d3e48e09c` | `b5fbfd500cc7b309bc9ddd15700714135d41693505adc93e4e20c0412b8e1a2b` |

The CSV files and `expected_conversion.json` are compatibility evidence only.
They are never parsed by the Godot runtime and are not shipped as authored
activity content. The converter keeps translated equations only under
`compatibility_assertions`; runtime drafts contain generator parameters and
fixed answers, never legacy display tokens or executable expressions.

No raster, audio, credentials, personal data, or other legacy assets were
copied into this directory.
