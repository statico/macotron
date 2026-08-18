const WORDS = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua".split(" ");

function generate(count, unit) {
    const n = Math.max(1, Number(count) || 1);
    if (unit === "words") {
        return Array.from({ length: n }, (_, i) => WORDS[i % WORDS.length]).join(" ");
    }
    if (unit === "lines") {
        return Array.from({ length: n }, () =>
            Array.from({ length: 8 }, (_, i) => WORDS[i % WORDS.length]).join(" ")
        ).join("\n");
    }
    return Array.from({ length: n }, () => {
        const sentences = Array.from({ length: 4 }, (_, s) => {
            const start = (s * 5) % WORDS.length;
            const body = Array.from({ length: 12 }, (_, i) => WORDS[(start + i) % WORDS.length]).join(" ");
            return body.charAt(0).toUpperCase() + body.slice(1) + ".";
        });
        return sentences.join(" ");
    }).join("\n\n");
}

macotron.command("Generate Lorem Ipsum", "Copy placeholder text to the clipboard", (args) => {
    const text = generate(args.count, args.unit);
    macotron.clipboard.set(text);
    macotron.notify.show("Lorem ipsum", "Copied " + args.count + " " + args.unit);
}, {
    id: "lorem-ipsum",
    arguments: [
        { name: "count", type: "number", placeholder: "Count", default: 3 },
        {
            name: "unit",
            type: "dropdown",
            placeholder: "Unit",
            default: "paragraphs",
            choices: [
                { title: "Words", value: "words" },
                { title: "Lines", value: "lines" },
                { title: "Paragraphs", value: "paragraphs" },
            ],
        },
    ],
});
