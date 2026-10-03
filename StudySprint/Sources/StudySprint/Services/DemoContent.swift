import Foundation
import StudySprintCore

/// A complete, hand-written sample sprint so people can explore the app before adding an API key.
/// Video links are YouTube searches (not specific videos), so nothing here is a made-up URL.
enum DemoContent {
    static func video(_ title: String, channel: String, duration: String, tip: String,
                      start: Int = 0, end: Int = 0, speed: Double = 1.5) -> VideoResource {
        VideoResource(title: title, url: YouTube.searchURL(for: "\(title) \(channel)"), channel: channel,
                      duration: duration, watchTip: tip, startSeconds: start, endSeconds: end,
                      playbackSpeed: speed, verified: false)
    }

    static func guide() -> StudyGuide {
        var g = StudyGuide(
            topic: "Cellular Respiration",
            emoji: "🧬",
            timeBudgetMinutes: 60,
            tldr: "Cells turn the energy in glucose into **ATP**, the cell's spendable energy. It happens in stages: **glycolysis** splits glucose, the **Krebs cycle** strips off high-energy electrons, and the **electron transport chain** uses those electrons to pump protons and drive ATP synthase. Oxygen is the final electron catcher — without it, the chain jams.",
            paretoConcepts: [
                "**ATP is energy currency**: respiration exists to recharge ADP → ATP.",
                "**Electrons are the real payload**: NADH and FADH₂ carry them to the electron transport chain.",
                "**Most ATP comes from the proton gradient** (chemiosmosis), not from glycolysis or Krebs.",
                "**Oxygen is the final electron acceptor** — that's why you need to breathe.",
            ],
            steps: [
                StudyStep(
                    title: "The big picture: why cells burn glucose",
                    minutes: 8,
                    why: "Every later step is one piece of this one equation.",
                    explanation: "C₆H₁₂O₆ + 6 O₂ → 6 CO₂ + 6 H₂O + **~30–32 ATP**.\n\nThink of it as controlled burning. Fire releases glucose's energy all at once as heat; cells release it in small steps so they can capture it as ATP.\n\n**Worked example:** one glucose → about 30 ATP. A muscle cell sprinting burns millions of ATP per second, which is why it needs a steady supply of glucose *and* oxygen.",
                    analogy: "Glucose is a $100 bill; ATP is quarters for the vending machines. Respiration is the change machine — it breaks the bill down into something the cell can actually spend.",
                    keyPoints: ["Inputs: glucose + O₂", "Outputs: CO₂ + H₂O + ATP", "Purpose: regenerate ATP from ADP + Pᵢ"],
                    videos: [video("Cellular respiration overview", channel: "Amoeba Sisters", duration: "7:42",
                                   tip: "Watch the first half for the stage map; skip the review at the end.", start: 20, end: 240)],
                    activeRecall: ["What are the inputs and outputs of cellular respiration?",
                                   "Why don't cells just 'burn' glucose all at once?"],
                    testOut: TestOut(question: "In one or two sentences: what is the overall purpose of cellular respiration and what are its inputs and outputs?",
                                     answer: "Make ATP from glucose's energy; glucose + O₂ in, CO₂ + H₂O + ATP out."),
                    prerequisites: []
                ),
                StudyStep(
                    title: "Glycolysis: splitting glucose",
                    minutes: 10,
                    why: "It's the first stage and happens in every living cell, with or without oxygen.",
                    explanation: "In the **cytoplasm**, one glucose (6 carbons) is split into **2 pyruvate** (3 carbons each).\n\n- Spend 2 ATP to get started (investment phase)\n- Make 4 ATP + 2 NADH (payoff phase)\n- **Net: 2 ATP, 2 NADH, 2 pyruvate**\n\nNo oxygen needed — that's why it's ancient and universal.",
                    analogy: "Like a startup: invest $2, earn back $4, net $2 profit — plus two IOUs (NADH) to cash in later.",
                    keyPoints: ["Location: cytoplasm", "Net yield: 2 ATP + 2 NADH", "Anaerobic — doesn't need O₂"],
                    videos: [video("Glycolysis explained", channel: "Khan Academy", duration: "11:20",
                                   tip: "Don't memorize every enzyme — focus on inputs, outputs, and net ATP.", start: 0, end: 420, speed: 1.75)],
                    activeRecall: ["Where does glycolysis happen?", "What is the net ATP yield of glycolysis, and why isn't it 4?"],
                    testOut: TestOut(question: "Where does glycolysis happen and what does it produce (net)?",
                                     answer: "Cytoplasm; 2 pyruvate, net 2 ATP, 2 NADH; no oxygen required."),
                    prerequisites: [1]
                ),
                StudyStep(
                    title: "Krebs cycle: harvesting electrons",
                    minutes: 12,
                    why: "This is where the carbon from glucose leaves as CO₂ — and where most electron carriers get loaded.",
                    explanation: "Pyruvate enters the **mitochondrial matrix**, becomes **acetyl-CoA**, and feeds the Krebs (citric acid) cycle.\n\nPer glucose (2 turns): **6 NADH, 2 FADH₂, 2 ATP, 4 CO₂** (plus 2 NADH + 2 CO₂ from pyruvate oxidation).\n\nThe big idea: the cycle barely makes ATP directly. Its real job is **loading electron carriers**.",
                    analogy: "A mine: the ore (carbon) is hauled away as CO₂ waste, but the gold (high-energy electrons) gets loaded into trucks (NADH, FADH₂) headed for the refinery.",
                    keyPoints: ["Location: mitochondrial matrix", "CO₂ is released here (that's the CO₂ you exhale)", "Main product: NADH and FADH₂, not ATP"],
                    videos: [video("Krebs cycle made simple", channel: "Ninja Nerd", duration: "14:05",
                                   tip: "Watch the summary section only; the step-by-step is optional for most exams.", start: 600, end: 845)],
                    activeRecall: ["Where does the CO₂ you exhale come from?", "Why do we say the Krebs cycle's main product is NADH, not ATP?"],
                    testOut: TestOut(question: "What is the main 'product' of the Krebs cycle, and where does it happen?",
                                     answer: "Loaded electron carriers (NADH, FADH₂) plus CO₂ and a little ATP; mitochondrial matrix."),
                    prerequisites: [2]
                ),
                StudyStep(
                    title: "Electron transport chain & chemiosmosis",
                    minutes: 15,
                    why: "This is where ~90% of the ATP is made — the payoff for everything before it.",
                    explanation: "NADH and FADH₂ drop electrons into a chain of proteins in the **inner mitochondrial membrane**. As electrons flow, the proteins **pump H⁺ ions** into the intermembrane space, building a gradient.\n\nH⁺ flows back through **ATP synthase**, which spins like a turbine and makes **~26–28 ATP**.\n\n**Oxygen** catches the spent electrons at the end (forming water). No O₂ → electrons back up → the whole chain stops.",
                    analogy: "A hydroelectric dam: electrons power pumps that push water (H⁺) uphill behind the dam; the water rushing back down through the turbine (ATP synthase) generates power (ATP).",
                    keyPoints: ["Location: inner mitochondrial membrane", "Proton gradient drives ATP synthase", "O₂ = final electron acceptor → H₂O", "Makes most of the ATP"],
                    videos: [video("Electron transport chain and ATP synthase animation", channel: "Harvard BioVisions", duration: "5:30",
                                   tip: "The animation of ATP synthase spinning is worth watching at normal speed.", speed: 1.0)],
                    activeRecall: ["What role does oxygen play in respiration?", "What actually powers ATP synthase?", "Why does cyanide (which blocks the chain) kill so fast?"],
                    testOut: TestOut(question: "Explain how the electron transport chain makes ATP, and why oxygen is required.",
                                     answer: "Electron flow pumps H⁺ to build a gradient; H⁺ flows back through ATP synthase making ATP; O₂ accepts electrons at the end so the chain keeps flowing."),
                    prerequisites: [3]
                ),
                StudyStep(
                    title: "No oxygen? Fermentation",
                    minutes: 7,
                    why: "A favorite exam question, and it ties the stages together.",
                    explanation: "Without O₂, the chain stops and NADH piles up. Glycolysis needs **NAD⁺** to keep going, so cells **regenerate NAD⁺** by fermentation:\n\n- **Lactic acid** (your muscles): pyruvate → lactate\n- **Alcoholic** (yeast): pyruvate → ethanol + CO₂\n\nFermentation itself makes **no extra ATP** — it just keeps glycolysis's 2 ATP coming.",
                    analogy: "When the refinery is closed, the trucks (NADH) dump their load on the roadside so they can go back for more — wasteful, but the mine keeps running.",
                    keyPoints: ["Purpose: regenerate NAD⁺", "Only 2 ATP per glucose (from glycolysis)", "Lactic acid vs alcoholic fermentation"],
                    activeRecall: ["Why does fermentation exist if it makes no ATP?", "Compare ATP per glucose: aerobic vs fermentation."],
                    testOut: TestOut(question: "What is the purpose of fermentation, and how much ATP does it make?",
                                     answer: "Regenerates NAD⁺ so glycolysis can continue; no extra ATP beyond glycolysis's net 2."),
                    prerequisites: [2, 4]
                ),
            ],
            flashcards: [
                Flashcard(front: "Overall equation for cellular respiration?", back: "C₆H₁₂O₆ + 6 O₂ → 6 CO₂ + 6 H₂O + ~30–32 ATP"),
                Flashcard(front: "Where does glycolysis occur?", back: "Cytoplasm"),
                Flashcard(front: "Net ATP from glycolysis?", back: "2 ATP (makes 4, spends 2)"),
                Flashcard(front: "Where does the Krebs cycle occur?", back: "Mitochondrial matrix"),
                Flashcard(front: "Main product of the Krebs cycle?", back: "Electron carriers: NADH and FADH₂ (plus CO₂)"),
                Flashcard(front: "What powers ATP synthase?", back: "H⁺ flowing down its gradient (chemiosmosis)"),
                Flashcard(front: "Final electron acceptor?", back: "Oxygen (forms water)"),
                Flashcard(front: "Purpose of fermentation?", back: "Regenerate NAD⁺ so glycolysis can keep running"),
                Flashcard(front: "Which stage makes the most ATP?", back: "Electron transport chain / oxidative phosphorylation (~26–28)"),
                Flashcard(front: "Where does exhaled CO₂ come from?", back: "Pyruvate oxidation and the Krebs cycle"),
            ],
            commonMistakes: [
                "Thinking the Krebs cycle makes most of the ATP — it mainly loads NADH/FADH₂.",
                "Saying oxygen is turned into CO₂. Oxygen becomes **water**; the CO₂ comes from glucose's carbons.",
                "Believing fermentation produces ATP itself — it only regenerates NAD⁺.",
            ],
            skipList: [
                "Names of all 10 glycolysis enzymes — rarely tested at intro level.",
                "Exact intermediates of the Krebs cycle (citrate → isocitrate …) unless your syllabus lists them.",
            ],
            mnemonics: [
                "**G-K-E** (\"Get Krebs Energized\"): Glycolysis → Krebs → Electron transport, in order.",
                "**OIL RIG**: Oxidation Is Loss, Reduction Is Gain (of electrons).",
            ],
            selfTest: [
                "Trace one glucose from glycolysis to water: where does each piece go?",
                "Why does a cyanide-poisoned cell switch to fermentation, and what happens to its ATP supply?",
                "Rank the stages by ATP produced and explain why.",
            ],
            sourceNotes: SampleNotes.all.first?.notes ?? "",
            sources: []
        )
        g.createdAt = Date()
        return g
    }
}
