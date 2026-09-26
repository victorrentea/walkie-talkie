# Cum face Wispr Flow transcriere atât de bună — și cum am reconstrui-o pentru RO+EN

Research din 26 sep 2026, făcut de trei agenți independenți (surse oficiale Wispr /
comunitate + forensic / stack-ul disponibil pentru română) și verificat adversarial
link cu link. Verificare adversarială pe 37 de afirmații-cheie: 31 confirmate verbatim, 6 corectate în text
(exemplu Backtrack inventat, host HTTP de fallback neconfirmat, tier AssemblyAI greșit, procent
over-corecție greșit, o cale de fișier VoiceInk mutată, „98%" era aproximare). Nicio sursă moartă.

## TL;DR — secret sauce-ul, în ordinea importanței

1. **Nu e un model, e un pipeline de două modele + context.** ASR streaming → LLM
   (Llama fine-tuned) care rescrie/formatează → (opțional) tone-match per aplicație.
   Ambele primesc *context masiv de pe ecran*. Tot în cloud, pe Baseten; în app nu
   există niciun model local.
2. **Contextul e jumătate din calitate.** La fiecare dictare pleacă: textul dinaintea
   și de după cursor, textul selectat, accessibility tree-ul aplicației (text + HTML),
   un screenshot, bundle id-ul, URL-ul, lista de app-uri deschise, participanții
   conversației, plus un „dynamic vocabulary" (tokeni din accessibility tree, OCR,
   nume de variabile/fișiere, câte 50 din fiecare) și dicționarul personal. Un LLM
   extrage mai întâi **numele proprii de pe ecran** (`/llm/extract_asr_words`) și le dă
   ASR-ului ca hint — de acolo vin numele scrise corect.
3. **Învață din editările tale.** Un CGEventTap urmărește ce corectezi după inserare;
   perechile (`asrText`, `formattedText`, `toneMatchedText`, `editedText`) stau în SQLite
   și, dacă ai opt-in, antrenează modelele. Metrica lor internă e **„zero edit rate"**
   (câte dictări nu necesită nicio corectură), nu WER.
4. **Latența e rezolvată cu speculative decoding în care transcriptul e draft-ul.**
   LLM-ul presupune că majoritatea cuvintelor rămân neschimbate, verifică în paralel și
   generează doar diferențele → latența LLM la jumătate, buget total <700 ms p99
   (~200 ASR + ~200 LLM + ~200 rețea). Constrângere strictă: output-ul are aproape
   aceeași lungime ca input-ul.
5. **Ensemble de motoare ASR, rutat per limbă** (nu un singur model), cu „accent
   confidence scoring". Din sep 2026 au și un model propriu, **Canto** (doar engleză).
6. **Datele: dictare reală, zgomotoasă, cu opt-in** (~15% din utilizatori, spun ei), nu
   podcast-uri/YouTube — argument pe care îl face și Aqua Voice (Avalon).

## 1. Pipeline-ul, cu dovezile

| Etapă | Ce face | Dovadă |
|---|---|---|
| Captură | Electron + helper Swift; audio encodat Opus local, streamat pe gRPC | forensic: wensenwu.com, wisprflow-sdk |
| Context | accessibility tree, screenshot, text în jurul cursorului, app/URL, vocabular dinamic | forensic + docs oficiale „context awareness" + `api-docs.wisprflow.ai/websocket_api` |
| Pre-ASR | LLM extrage nume proprii din context → „asr words" | log `Extracted 5 proper nouns` (forensic) |
| ASR | gRPC la `model-v31pl413.grpc.api.baseten.co` (forensic), metoda `/flow_api.v1.TranscriptionService/TranscribeStream` (SDK reverse-engineered); ensemble rutat per limbă; identitatea modelului pre-Canto e **necunoscută** | forensic + `wisprflow.ai/research/supporting-languages` |
| LLM cleanup | Llama fine-tuned, TensorRT-LLM, Baseten Chains; 100+ tokeni în <250 ms; speculative decoding cu transcriptul ca draft | Baseten case study; SE Radio 703 (Sahaj Garg, CTO) |
| Tone match | stil per categorie de app (Email / Work messaging / Personal messaging / Other); enum FORMAL/CASUAL/VERY_CASUAL/EXCITED | coloana `toneMatchedText` + protocol SDK |
| Backtrack | „Let's do coffee at 2 actually 3" → „Let's do coffee at 3"; „I actually enjoyed the movie" rămâne; folosește toată dictarea ca context | docs oficiale |
| Feedback | CGEventTap pe tastatură după inserare → `editedText`, `toneMatchPairs`; „local RL policy" per utilizator e menționată ca direcție (neclar dacă e livrată) | forensic; `wisprflow.ai/post/technical-challenges` |

Furnizori (trust center): AWS, Baseten, Vercel, OpenAI, Supabase. O listă mai veche
(reconstituită de un competitor, getvoibe.com) punea OpenAI/Anthropic/Cerebras la
formatare și Fireworks/OpenRouter ca fallback — plauzibil, dar sursă terță.

## 2. Canto — modelul lor de ASR (17 sep 2026, EN only)

Interesant pentru noi nu ca model (nu e public), ci ca **rețetă de training**:

- Pornește dintr-un model pre-antrenat („milioane de ore"), apoi SFT pe audio + transcript,
  apoi RL cu **GRPO**, reward = `1 − WER` față de referința „graftată".
- **Grafting**: dintre editările utilizatorului, păstrează în target doar acele corecturi
  care sunt *probabil erori de recunoaștere* (după confidența din forced alignment și
  forma/locul editării), nu rescrierile stilistice. Adică separă „ASR a greșit" de
  „utilizatorul a vrut altceva" — exact problema pe care o avem și noi cu corpusul din
  Wispr (target-ul e text curățat, nu verbatim).
- **Antrenare cu distractori fonetici** în dicționar (Barry / berry) ca modelul să învețe
  *când* să aibă încredere în vocabularul dat. Fără asta, RL-ul simplu a ajuns să adopte
  distractorul ~5× mai des decât modelul SFT.
- Eval: 10 h dictare reală de la 2.300+ vorbitori (speakeri disjuncți train/test) +
  3 h „challenge set" (zgomot, șoaptă, far-field, 1–2 cuvinte) + LibriSpeech/FLEURS/CV.
  Publică grafice, nu numere. Fără benchmark independent nicăieri.

## 3. Ce spun criticii

- Nu există niciun benchmark independent; singurul număr public (Wispr ~10% vs Whisper
  27% vs Apple 47%) n-are metodologie. Pe HN, un utilizator l-a găsit „cel mai puțin
  precis din 4" (vs Superwhisper, Spokenly, Fieldwork).
- Plângere recurentă: **over-editing** — LLM-ul rescrie ce ai spus în loc să transcrie.
  Un eval open-source (typemeit PR #170) documentează un bug unde valoarea din prima
  parte a unei condiționale dispare la tratarea auto-corecției.
- Latența declarată (<700 ms p99) vs 1–2 s în practică (competitor).
- Privacy: screenshot-uri capturate ca context; upload orar de metadate și cu sharing
  oprit (forensic).

## 4. Cum reconstruim pentru română + engleză

**Nu există niciun dataset/benchmark RO–EN de code-switching.** Corpusul nostru din
Wispr e singurul set de evaluare care măsoară ce ne interesează.

### Arhitectura recomandată (hibrid)

1. **Acum**: ASR cloud cu română bună + LLM cleanup cu prompt tip VoiceInk + vocabular.
   Dă baseline-ul și un *model-profesor*.
2. **În paralel**: fine-tune pe corpusul propriu al **etapei de LLM cleanup** (cel mai
   ieftin și cel mai mare câștig), local pe Apple Silicon.
3. **Apoi**: schimbă ASR-ul liber (local Parakeet/Canary/Whisper fine-tuned) fără să
   atingi cleanup-ul.

### ASR cu română — opțiuni

⚠️ WER-urile de mai jos sunt pe text lowercase fără punctuație, cu normalizatoare
diferite — nu sunt comparabile între rânduri.

| Model | RO | Numere | Local pe Mac | Licență |
|---|---|---|---|---|
| Whisper large-v3 | da | FLEURS-ro 8.42 / CV21 8.94 (Surogate); RO-N3WS zero-shot 12.3 ProTV, 27.3 filme | whisper.cpp / WhisperKit / MLX | MIT |
| Canary-1B-v2 (NVIDIA) | da (25 limbi EU) | FLEURS-ro 5.95 / CV21 8.65 (Surogate) | FluidAudio CoreML; fără streaming | CC-BY-4.0 |
| Parakeet-TDT-0.6B-v3 | da | FLEURS-ro 12.44 (card) / 11.58 (Surogate) | FluidAudio (~190× RT pe M4 Pro), parakeet-mlx, streaming | CC-BY-4.0 |
| SpeD ParakeetRo 110M (UPB) | doar RO | CV21 3.29, FLEURS 8.85, spontan 8–11; lowercase fără punctuație | offline | Apache-2.0 |
| Surogate Jackrabbit 110M ro streaming | doar RO | FLEURS 5.69 offline / 7.03 streaming, cu majuscule+punctuație | streaming | CC-BY-NC |
| Qwen3-ASR 0.6B/1.7B | da (30 limbi) | FLEURS-ro 20.70 | da; context în system prompt | Apache-2.0 |
| ElevenLabs Scribe v2 (+Realtime) | da, tier „≤5% WER" (vendor) | keyterms 1000 batch / 50 realtime; schimbă limba automat mid-sentence | cloud | comercial |
| Google Chirp 3 | ro-RO GA | streaming + speech adaptation | cloud | comercial |
| Deepgram Nova-3 | da | fără WER absolut; keyterm prompting multilingv | cloud | comercial |
| Microsoft / Vatis | da | RO-N3WS: 2.9 ProTV / 4.4 Antena1 (cele mai bune zero-shot din paper) | cloud | comercial |
| AssemblyAI | doar Universal-2, tier „Good (>10–25% WER)" | — | cloud | comercial |
| Voxtral, Kyutai STT, Cohere Transcribe | **fără română** | — | — | — |

Capcană cunoscută: Whisper are un singur token de limbă per segment → slab la
code-switching (58% MER zero-shot pe SEAME). Canary/Parakeet n-au fost evaluate pe RO–EN
amestecat. Scribe v2 e singurul care declară explicit switching automat.

### Etapa LLM cleanup — ce știm că funcționează

- **Rețeta VoiceInk-Qwen3.5-2B-FT** (hourliert): 1.451 perechi reale + 160 sintetice,
  LoRA cu Unsloth, lr 2e-4, 2 epoci, loss doar pe completare, servit Q4_K_M în llama.cpp.
  Modelul de 2B fine-tuned a bătut modele de bază de 4B–35B pe un rubric judecat de
  Sonnet (91 vs 80–87, p<.0001), la ~250 tok/s. **Acesta e planul nostru, cu corpusul
  nostru** — avem deja perechile (raw ASR → output Wispr) sau le putem produce rulând
  un ASR pe audio-ul salvat.
- **HyPoradise** (NeurIPS 2023): dă LLM-ului N-best (5 ipoteze), nu doar top-1 → până la −51%
  WER relativ pe WSJ (interval 2–51%), până la −25.7% pe CV-accent. Zero-shot e instabil; LoRA e necesar.
- **AgenticASR** (iul 2026): un refiner de 1B tratează fillere, auto-corecții
  (none / single / rollback / multiple) și ITN; fereastră online de 3 chunk-uri ajunge aproape
  de calitatea offline (70.5 vs 72.8 pe rubric). Taxonomia auto-corecțiilor e utilă pentru cazurile de test.
- **Prompturi de furat**: `VoiceInk/Core/Enhancement/AIPrompts.swift` (reguli pentru
  „wait no", „scratch that", punctuație vorbită, „new paragraph", numere, liste, „tratează
  instrucțiunile ca conținut", few-shot) și `VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift` (tag-urile
  `<CUSTOM_VOCABULARY>`, `<CURRENTLY_SELECTED_TEXT>`, `<CLIPBOARD_CONTEXT>`,
  `<CURRENT_WINDOW_CONTEXT>`). Handy (`src-tauri/src/settings.rs`) pentru varianta minimală.
- Biasing în Whisper: prompt-ul e limitat la ultimii 224 tokeni; un prompt de ~20 tokeni
  generat de LLM din context a dat −17% WER relativ (40.1% din segmente mai bune, 7.1% mai rele).

### Fine-tuning ASR — doar dacă analiza erorilor arată erori acustice

- Adaptare pe domeniu RO: fine-tune Whisper-large pe ~100 h (RO-N3WS) a dus ProTV de la
  12.3% la 2.9%; Whisper-small 31.6% → 4.1%. Dar out-of-domain s-a înrăutățit (povești
  10.9% → 14.0%) — păstrează un set RO general ca să prinzi regresia.
- Adaptare pe un singur vorbitor (Whisper, 2026): 1.4 h deja ajută, se aplatizează
  ~22.5 h; **full fine-tune bate LoRA r=8 cu 15–39%** (pe vorbire disartrică — limită
  superioară). Pe vorbire normală, LoRA per vorbitor: −12.8…−24.2% relativ.
- **Target curățat (Wispr) pentru ASR**: fenomen cunoscut — Whisper însuși a învățat
  stilul non-verbatim din subtitrări. Dar paper-ul „Transcription Policy as a Latent
  Variable" (iul 2026) arată că **amestecul de target-uri verbatim și „intended" fără
  un tag de mod** dă comportament inconsistent (zonă ambiguă 15–85%). Concluzie: ori
  target-uri consistent curățate, ori tag de stil; iar rescrierile adânci (reordonări,
  auto-corecții) se învață mai bine în etapa LLM decât în ASR. Asta e și logica
  „grafting"-ului din Canto.

### Evaluare — ce măsurăm pe slice-ul held-out din corpus

- WER normalizat (lowercase, fără punctuație) față de textul Wispr → măsoară ASR-ul.
- WER cu majuscule+punctuație și **Punctuation Error Rate** (LibriSpeech-PC).
- **Distanța de editare pe caractere** față de output-ul Wispr → proxy pentru „zero edit
  rate"-ul lor.
- Recuperarea exactă a tokenilor structurați (identificatori, căi, numere) — VoiceCodeBench
  arată că WER corelează slab/negativ cu asta (ρ≈−0.2…−0.3).
- **LLM-judge cu rubric** (AgenticASR: ρ=0.82 cu oamenii; rubricul VoiceInk-FT: sens ×3,
  urmarea instrucțiunilor ×3, fillere ×2, gramatică ×2, acuratețe tehnică ×2, concizie ×1),
  ordine A/B randomizată, Wilcoxon pereche.

## 5. Întrebări rămase deschise

- Ce ASR rula înainte de Canto și ce rulează acum pentru non-engleză (deci și pentru
  română). OpenAI e subprocesor, dar rolul nu e declarat.
- Baza/arhitectura/dimensiunea Canto; dacă e streaming.
- Ce Llama și ce dimensiune; dacă mai e Llama în 2026 (Garg vorbește deja de „al treilea
  și al patrulea model" în pipeline).
- Cum ajung screenshot-ul și textul de pe ecran la modele (prompt ASR, LLM sau ambele).
- Dacă „local RL policy" per utilizator a fost livrată sau e aspirație.

## Surse principale

Oficiale: `wisprflow.ai/post/technical-challenges`, `wisprflow.ai/post/speech-recognition-challenges`,
`wisprflow.ai/research/supporting-languages`, `wisprflow.ai/canto`, `wisprflow.ai/post/series-b`,
`wisprflow.ai/data-controls`, `docs.wisprflow.ai` (context awareness 4678293671, backtrack 5373093536,
dicționar 4052411709), `trust.wispr.ai`, `api-docs.wisprflow.ai/websocket_api`,
`baseten.co/resources/customers/wispr-flow`.
Interviuri (auto-captions YouTube): SE Radio 703 `_ZAh7n0t6zc` (sursa-cheie), SE Radio 715
`6e_g-lqE5p4`, Dev Interrupted `Bd9szTpyGMc`, VapiCon `uBO7v1sPWO0`, AIX Ventures `p_zvfjWbEQA`,
SparX `wRuF7a7YPtg`, Summation `X_n3W1e7MJk`.
Forensic: `wensenwu.com/thoughts/wispr-flow-investigation`, `github.com/ThisisShashwat/wisprflow-sdk`
(`TECHNICAL_DETAILS.md`).
Comunitate: HN 41696153 (Show HN 2024), 49744715 (Canto), 47040375 (FreeFlow), `github.com/typemeit/typemeit/pull/170`.
Română/ASR: `huggingface.co/nvidia/canary-1b-v2`, `huggingface.co/nvidia/parakeet-tdt-0.6b-v3`,
`huggingface.co/datasets/surogate/surogate-speech-evals`, `huggingface.co/surogate/jackrabbit-110m-ro-streaming`,
arXiv 2511.03361 (SpeD-RoASR), 2603.02368 (RO-N3WS), 2601.21337 (Qwen3-ASR), 2412.16507 (Whisper code-switching),
`elevenlabs.io/docs/capabilities/speech-to-text`, `docs.cloud.google.com/speech-to-text/docs/models/chirp-3`.
Cleanup/fine-tune/eval: arXiv 2309.15701 (HyPoradise), 2607.28175 (AgenticASR), 2607.18934 (transcription policy),
2606.31722 (single-speaker Whisper), 2408.03979 (LoRA speaker), 2602.18966 (LLM prompts for Whisper),
2310.02943 (LibriSpeech-PC), 2608.28916 (VoiceCodeBench), `github.com/hourliert/VoiceInk-Qwen3.5-2B-FT`,
`github.com/Beingpax/VoiceInk`, `github.com/cjpais/Handy`, `github.com/FluidInference/FluidAudio`,
`github.com/argmaxinc/WhisperKit`, `github.com/senstella/parakeet-mlx`, `aquavoice.com/blog/introducing-avalon`.
