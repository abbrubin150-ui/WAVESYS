# צווי פיתוח מעודכנים — Neuro-Lingua v4

המסמך מרכז את סדר השלבים המומלץ לשדרוג ארכיטקטורת ה-Transformer ב-Neuro-Lingua ליעדי v4: מעבר ל-RoPE, SwiGLU, RMSNorm ו-Mirostat v2. התכנון מודגש כך שיופעלו בדיקות יציבות לפני שינויים ארכיטקטוניים משמעותיים.

## סדר פיתוח מוצע

0. **הכנה וייצוב**
   - לאשר שמבחני נומריקה מכסים `softmax` / `logsumexp` והתמודדות עם overflow.
   - להוסיף או להדק בדיקות התאמה CPU↔GPU כדי לצמצם רעשי רגרסיה לפני החלפת רכיבי ליבה.

1. **מעבר לנורמליזציה מודרנית**
   - להחליף Batch Renorm / LayerNorm ב-RMSNorm ולהעדיף Pre-Norm בבלוקים.
   - TransformerLM כרגע משתמש ב-Batch Renorm + dropout עם position embeddings נלמדים; המעבר ל-RMSNorm הוא הכנת תשתית.
   - לעדכן: `src/lib/TransformerLM.ts`, טבלאות השוואה ודוקומנטציה, ו-Architecture Presets ב-`src/components/TrainingPanel.tsx` כדי שפריסט ה-Transformer יפעיל את הדגלים והברירות החדשות.

2. **שדרוג FFN לשער מודרני**
   - להחליף את ה-FFN ל-SwiGLU לאחר שהנורמות מוחלפות.

3. **החלפת positional encoding**
   - להחליף learned position embeddings ב-RoPE כחלק מהיעדים של v4.

4. **שדרוג דקודינג (נפרד מהאימון)**
   - להוסיף Mirostat v2 כמצב דגימה חדש.
   - לעדכן: `src/generation/sampler.ts`, ממשק ה-UI ב-ChatInterface, ובדיקות sampler.

5. **התאמות קונפיגורציה ומדיניות**
   - לעדכן `DEFAULT_GENERATION` ו-`DEFAULT_HYPERPARAMETERS`.
   - לעדכן המלצות ל-"Recommended TransformerLM Configuration".

6. **אופציונלי לאחר v4 בסיסי**
   - GQA ליעילות קשב.
   - YaRN / הרחבת חלון הקשר.

## הערות סדר והיגיון
- RMSNorm + Pre-Norm הם בסיס ליציבות; בלעדיהם RoPE ו-SwiGLU עלולים להקשות על אבחון.
- SwiGLU טבעי אחרי הטמעת הנורמליזציה החדשה.
- RoPE נשען על בלוק קשב "נקי" ולכן מגיע אחרי ניקוי הנורמות וה-FFN.
- Mirostat v2 הוא שדרוג דקודינג שניתן לשחרר גם בלי להמתין לכל שינויי האימון.

## צ׳ק-ליסט קבצים ומודולים
- `src/lib/TransformerLM.ts`
- `src/models/attention.ts` או `src/models/mini_transformer.ts`
- `src/config/constants.ts`
- `src/components/TrainingPanel.tsx`
- `src/generation/sampler.ts`
- `tests/TransformerLM.test.ts`, `tests/sampler.test.ts`, ו-`tests/numerics/*`

