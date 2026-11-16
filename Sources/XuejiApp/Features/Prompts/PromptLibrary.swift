import Foundation

/// A ready-made prompt for an AI assistant. The text is in English, which every assistant follows well; it asks
/// for the exact layout that one of Xueji's importers reads.
struct PromptTemplate: Identifiable, Equatable {
    /// Also the suffix of the strings "prompts.<id>.title", ".use" and ".where".
    let id: String
    let symbol: String
    let text: String
}

enum PromptLibrary {
    static let all: [PromptTemplate] = [sourceTriage, statements, evidenceReport, references]

    // MARK: Source triage (Inbox › Import PDF › Source triage)

    static let sourceTriage = PromptTemplate(id: "sourceTriage", symbol: "list.number", text: """
    You are helping me find and triage sources for a research project. Work in the order below and give me ONE document (Word .docx or PDF) with exactly the structure at the end. Put nothing before the table except a title.

    TOPIC: [the research question, the period it covers, the languages of the sources]
    HOW MANY: [for example 20 to 30 sources]
    ALREADY HAVE (optional): [titles or links, so you do not repeat them]

    If the topic is too vague to search well (no clear question, period or field), ask me up to three short questions first. Otherwise start.

    HOW TO SEARCH
    1. Split the topic into 2 to 5 periods or phases. Every source in the table belongs to one of them.
    2. Search each period with several different wordings, and in every language I listed. Look first for scholarly work (journals, university presses, working papers), then think tanks, official documents and quality media. Follow the references of the best works to find the ones that everybody cites.
    3. Cover different views, including the ones that disagree with the likely answer, and both the foundational older works and the recent ones.
    4. Open every link before you list it and check that the title, the year and the venue match what the page shows. If you cannot open it or cannot confirm it, leave it out. Never invent a source, a link or a detail. A paywalled work is fine when its page opens and the details match.
    5. Prefer fewer sources that you checked over many doubtful ones.

    HOW TO CLASSIFY
    - ESSENTIAL: central to the question, or the work that others build on. Read it first.
    - COMPLEMENTARY: adds a perspective, a case or evidence that the essential ones lack.
    - SECONDARY: background or context.
    A good list has only a few ESSENTIAL sources in each period and mixes the three classes.

    STRUCTURE OF THE DOCUMENT

    1. A table whose heading row has exactly these six columns, in this order:
       #  |  Period  |  Source  |  Link  |  Classification  |  Triage note
       - "#": 1, 2, 3… one number per row.
       - "Period": the phase of the topic the source belongs to, for example "Period 1 (2010-2015)".
       - "Source": Title (Year) (Venue / Publisher). No authors in this cell.
       - "Link": the site and a shortened path, written "site › path", for example "jstor.org › stable/123". Only links you checked open.
       - "Classification": exactly one of ESSENTIAL, COMPLEMENTARY or SECONDARY, in capitals. ESSENTIAL = central, read first. COMPLEMENTARY = adds a perspective or evidence. SECONDARY = background.
       - "Triage note": one or two sentences on what it gives me and why it has that classification.
       Sort by period, then by importance.

    2. Under the table, a heading "Suggested Reading Order" and a numbered list written like this:
       1. [row number] Title — why it comes here
       2. [row number] Title — why it comes here
       Each [row number] is the "#" of the table row.

    Use a real table (not Markdown text, not an image) and keep the six column headings exactly as written. I will save the document as a PDF.

    AFTER THE DOCUMENT, in your reply here (not inside the document), tell me in a few lines: which periods or views are thin, which searches found nothing, and which links you could not open.
    """)

    // MARK: Who said what and when (Inbox › Import PDF › Statements)

    static let statements = PromptTemplate(id: "statements", symbol: "text.bubble", text: """
    You are helping me map who said what, and when, about a topic. Work in the order below and give me ONE document (Word .docx or PDF) with exactly the structure at the end.

    TOPIC: [the topic, the actors or countries of interest, the years]
    HOW MANY: [for example 15 to 30 statements]

    If the topic is too vague to search well (no actors, no years), ask me up to three short questions first. Otherwise start.

    HOW TO SEARCH
    1. List the actors that matter (people, governments, institutions, think tanks, media) and split the years into periods. Then look for what each actor said in each period.
    2. Go to the original: transcripts, official statements, speeches, hearings, interviews, reports. A statement quoted second-hand is a last resort; if you use one, say so in "Where".
    3. Give the exact date. Use quotation marks only for words taken exactly as they were said; otherwise write a faithful paraphrase. Never put words in someone's mouth, and never attribute a view to someone without a source that you opened.
    4. Include voices that disagree and actors from each side. When an actor changed position, show both statements.
    5. Open every link before you list it and check that the page says what you report. If you cannot confirm a statement, leave it out and mention it under "Caveats".

    STRUCTURE OF THE DOCUMENT

    1. The statements, grouped under period headings. Each heading is a line of its own, at the left margin, written "Period 1 (2010-2013)", "Period 2 (2014-2016)"… Under each heading, a table whose heading row is exactly:
       Date  |  Who  |  Position  |  Where  |  Ref
       - "Date": "13 Jul 2011" when exact; "Nov 2016" or "2010" when only the month or year is known; "c. 31 Jul 2016" when approximate.
       - "Who": the name, then a type code in brackets: (S) scholar, (TT) think tank, (M) media, (C) citizens, (G) government. After the code, if useful, the setting of the statement. Example: "Jane Smith (S) at a conference in Delhi".
       - "Position": what the person or body said, in one to three sentences, close to their own words.
       - "Where": the document and the page or section where it can be found.
       - "Ref": the reference number in square brackets, for example [3]. If several references support it, put each on its own line.
       Repeat the heading row under every period heading.

    2. After the last table, a line with only the word "References", then a numbered list, one entry per number used in the "Ref" column:
       1. Author, Title, Publisher or Journal, Year, pp. 10-20.
       2. Author. “Title.” Journal, Vol.12, No.3, 2019, pp.1-45
       Add the link (https://…) at the end of web sources and give the full link, even if it is long.

    3. At the very end, a line starting with "Caveats:" for what you could not confirm.

    Use real tables (not Markdown text, not images) and keep the column headings exactly as written. I will save the document as a PDF.

    AFTER THE DOCUMENT, in your reply here (not inside the document), tell me in a few lines which actors or periods are thin and which searches found nothing.
    """)

    // MARK: Evidence report (Evidence › Import)

    static let evidenceReport = PromptTemplate(id: "evidenceReport", symbol: "quote.bubble", text: """
    You are helping me triage quotations about a term in a set of documents. Read the documents I attach (or search for them if I give you a list of titles) and give me ONE document (Word .docx or PDF) with exactly the structure below. English is the default; if I ask for Chinese, use the Chinese headings in brackets.

    SEARCH TERM: [the term, for example "national security"]    DOCUMENTS: [attached / the list]

    HOW TO WORK
    1. Read every document in full. If you cannot open or read one (or it is a scan you cannot read), say so in the paragraph about the corpus and leave it out of the counts. Never guess a count, a quote, a page or a date.
    2. Count the term the same way in every document (whole word, ignoring capitals) and say how in the Method paragraph. Count the phrase of the "of which" column the same way.
    3. Quotes: copy them word for word, with the page or section where they appear, and check each one against the text before you list it. Choose the strongest ones across all the documents, not only the longest. Look on purpose for passages that cut against the argument (Counter), and say in "How the term is used" when a document talks about the idea without using the term.
    4. The timeline only holds events that the documents themselves show, with the date they give. Do not add events from your own knowledge.
    5. Draw no conclusion that the documents do not support. The recap says what the counts and the quotes show, and what they cannot show.

    STRUCTURE OF THE DOCUMENT

    First line: the title of the report. Second line: "Search term: <term> (<number> documents)"  [检索词：<term>（<number> 份文件）]. Then one short paragraph about the corpus (what the documents are, what is missing).

    1. A heading "1. Where the term appears", then a table whose heading row is exactly:
       #  |  Document  |  Date  |  Words  |  <term>  |  per 1,000 words  |  of which “<phrase> <term>”  |  How the term is used
       [# | 文件 | 日期 | 词数 | <term> | 每千词 | 其中“<phrase> <term>” | 该词如何使用]
       Count the exact term in each document, give the rate per 1,000 words, and count how many of those are the phrase in the "of which" column (leave the column out if there is no phrase). Under the table, one short caution about how to read the counts.

    2. A heading "2. The strongest quotes", then a table whose heading row is exactly:
       #  |  Quote  |  Speaker / locator  |  Class  |  Why it matters
       [# | 引文 | 发言人 | 类别 | 意义]
       - "Quote": the passage between quotation marks, word for word.
       - "Speaker / locator": who said it on the first line, then the document and the page or section on the next lines.
       - "Class": exactly one of Essential, Supporting or Counter (Counter = evidence against the argument).
       - "Why it matters": one sentence.

    3. A heading "3. Timeline", then TWO tables one after the other, with nothing between them.
       First the periods table, whose heading row is exactly:
       Period  |  From  |  Until  |  Inside  |  Quotes
       [时期 | 起 | 止 | 属于 | 引文]
       A period is a named stretch of time (for example "2019–2023 expansion"). Give each period a short, unique name.
       - "From" and "Until": a year (2019), a month (Feb 2019) or a day (4 Nov 2019).
       - "Inside": the name of the larger period that holds it, or leave it empty when it sits directly in the whole timeline. A period must fit inside the one it is inside.
       - "Quotes": the numbers (#) of the quotes of table 2 that belong to it, separated by commas, or empty.
       If there are no periods, leave this first table out.

       Then the events table, whose heading row is exactly:
       Date  |  Event  |  Who  |  What frame  |  Period  |  Quote #
       [日期 | 事件 | 发言方 | 框架 | 时期 | 引文 #]
       - "Date": written ONLY as a year (2019), a month (Feb 2019), a day (4 Nov 2019) or a period (2019–2023, Feb–Jun 2019, 4–5 Nov 2019). No other words in that cell.
       - "Period": the name of the period from the first table that holds the event, or empty.
       - "Quote #": the number (#) of the quote of table 2 that shows the event, or empty. If the date has no document in the corpus, write “—” in this cell instead.

    4. A heading "4. Recap" [4. 小结], then a numbered list of the findings (1. … 2. … 3. …), each in one or two sentences.

    5. A last paragraph starting with "Method" [方法] describing how you counted.

    The four headings must start with the numbers 1. to 4. Use real tables (not Markdown text, not images) and keep the column headings exactly as written. I will save the document as a PDF.

    AFTER THE DOCUMENT, in your reply here (not inside the document), list in a few lines what you could not open or check, and any quote whose page you are not sure of.
    """)

    // MARK: Reference list (References › Convert, and the Compile screen)

    static let references = PromptTemplate(id: "references", symbol: "text.quote", text: """
    Format the references below in the style I show. Give me only the numbered list, plain text, one entry per line, nothing else.

    STYLE (the "official model"):
    - Chinese journal article: 1. 胡仕胜，王珏：《印度对华示强外交的行为逻辑》，载《现代国际关系》，2020 年第 7期，第 25-34 页。
    - Chinese book: 2. 阎学通：《世界权力的转移：政治领导与战略竞争》，北京大学出版社，2015 年版，第3-34 页。
    - English journal article: 3. Surupa Gupta, et al. “Indian Foreign Policy Under Modi: A New Brand or Just Repackaging?.” International Studies Perspectives, Vol.20, No.1, 2019, pp.1-45
    - English book: 4. Thomas Christensen. Useful Adversaries: Grand Strategy, Domestic Mobilization, and Sino-American Conflict, 1947-1958. Princeton University Press, 1996. pp.11-13.
    - English chapter: 5. Harsh V. Pant. “Changing Contours of Indian Diplomacy Under Narendra Modi.” The Routledge Handbook of Diplomacy and Statecraft. Routledge, 2022. pp.135-145.
    - Web report: 6. Craig Kafura & Dina Smeltz, “Cooperation, Competition, or Confrontation? Republicans and Democrats Split on China Policy,” The Council Global Affairs, December 2021, https://globalaffairs.org/…, 访问时间：2024 年 7 月 1 日。

    RULES: keep my numbering; list up to three authors and use "et al." after that; do not invent pages, volumes, issues or links — if a detail is missing, leave it out and put "[?]" in its place. If you can look a work up online (the publisher's or the journal's page, or its DOI), use that page to complete the missing details, and use only what the page confirms.

    REFERENCES:
    [paste your list here]
    """)
}
