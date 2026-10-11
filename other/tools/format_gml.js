// GML formatter. Run with: node format_gml.js [--no-compact]
// First collapses single-statement braced if/for/while blocks onto one
// line (skip with --no-compact), then normalizes indentation and spaces
// inside single-line array literals, e.g.
//   [ c_red, c_lime, c_blue ]. Array accessors such as _comp[$ _m] are unchanged.
//
// Control-block spacing:
// - Add a blank line before and after if, for, and while blocks.
// - Do not add a blank line before a control block when it follows a comment,
//   a function declaration/body opening, another if, or a closing brace (including
//   the closing-brace line in `} else {`).
// - Do not add a blank line before the first statement inside a function, if,
//   for, or while body. This includes an if or while directly inside a for loop,
//   and a while directly inside an if block.
// - Do not add a blank line after a control block when the next code line is a
//   closing brace; remove an existing blank line there as well.
// - Keep else and else-if branches attached to the preceding if block.
//
// Continuation lines:
// - Lines inside unclosed parens/brackets indent one level past the statement
//   that opened the group; pure-closer lines (`);`, `];`) realign to it.
// - Lines starting with &&, ||, ? or : (or following a line ending with a
//   binary operator) align one past their statement's first line.
// - Runs of 2+ spaces after an if/for/while header's `)` collapse to one.

const fs = require("node:fs");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..", "..");
const ignoredDirectories = new Set([".git", "Build", "node_modules"]);
const ignoredFiles = new Set(["polygon_merged.gml"]);
const indentUnit = "  ";

function collectGmlFiles(directory, files = []) {
	for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
		if (entry.isDirectory() && !ignoredDirectories.has(entry.name)) {
			collectGmlFiles(path.join(directory, entry.name), files);
		} else if (entry.isFile() && entry.name.toLowerCase().endsWith(".gml") && !ignoredFiles.has(entry.name)) {
			files.push(path.join(directory, entry.name));
		}
	}

	return files;
}

function formatIndentation(source) {
	const newline = source.includes("\r\n") ? "\r\n" : "\n";
	const lines = source.split(/\r\n|\n/);
	// Stack entries: { ch, block, stmtDepth }. Braces always open blocks.
	// Parens/brackets open continuation groups: content lines inside them
	// indent one level past the statement that opened the outermost group,
	// and pure-closer lines realign to it.
	const delimiterStack = [];
	const depthOfLine = [];
	let inBlockComment = false;
	let quote = null;
	let escaped = false;

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const content = line.replace(/^\s+/, "");

		if (content.length === 0) {
			depthOfLine.push(null);
			continue;
		}

		// Preprocessor directives and lines inside a multiline literal keep their
		// original indentation; their contents can have language-specific meaning.
		if (quote !== null || content.startsWith("#")) {
			updateLexicalState(line, 0);
			depthOfLine.push(null);
			continue;
		}

		// Peek at leading closers WITHOUT mutating the stack (the single
		// pop site stays updateLexicalState below; popping twice here
		// would drain one block level per `}` line).
		const popped = [];
		let rest = content;
		let tempTop = delimiterStack.length - 1;
		while (rest.length > 0) {
			const c = rest[0];
			if (c !== ")" && c !== "]" && c !== "}") break;
			const top = delimiterStack[tempTop];
			const expected = c === ")" ? "(" : c === "]" ? "[" : "{";
			if (!top || top.ch !== expected) break;
			popped.push(top);
			tempTop--;
			rest = rest.slice(1);
		}

		const blockDepth = delimiterStack.reduce((n, e) => n + (e.block ? 1 : 0), 0) -
			popped.reduce((n, e) => n + (e.block ? 1 : 0), 0);
		const hasGroup =
			delimiterStack.some((e) => !e.block) || popped.some((e) => !e.block);
		const restTrim = rest.trim();
		let depth;

		if (!hasGroup) {
			depth = Math.max(0, blockDepth);
		} else if (restTrim === "" || /^[,;]+$/.test(restTrim)) {
			// Pure-closer line: realign to the statement that opened the
			// outermost group closed here (or to the block depth).
			const poppedGroups = popped.filter((e) => !e.block);
			if (poppedGroups.length > 0) {
				depth = poppedGroups[poppedGroups.length - 1].stmtDepth;
			} else {
				depth = Math.max(0, blockDepth);
			}
		} else if (/[\)\]]\s*\{\s*(?:\/\/.*)?$/.test(rest)) {
			// Line closes a group into a block opening (e.g. `cond) {`):
			// align with the statement that opened the group.
			const top = delimiterStack[delimiterStack.length - 1];
			const groups = delimiterStack.filter((e) => !e.block);
			depth = groups.length > 0 ? groups[groups.length - 1].stmtDepth : Math.max(0, blockDepth);
			void top;
		} else {
			// Content inside a group: one level past the innermost
			// open group's statement.
			const top = delimiterStack[delimiterStack.length - 1];
			if (top && !top.block) {
				depth = top.stmtDepth + 1;
			} else {
				depth = Math.max(0, blockDepth);
			}
		}

		// Operator continuation without open groups: continuation lines of a
		// split statement all indent one past the statement's first line
		// (so `?`/`:` pairs and `&&` chains align instead of cascading).
		// A trailing comma never continues here (struct fields / array
		// elements either live in groups or keep block indent).
		if (!hasGroup && restTrim !== "" && !/^[,;]+$/.test(restTrim)) {
			const startsOp = /^(?:&&|\|\||\?|:)(?![=:])/.test(restTrim);
			if (startsOp || endsWithOperator(lines, i)) {
				const base = statementStartDepth(lines, depthOfLine, i);
				if (base !== null) depth = base + 1;
			}
		}

		depthOfLine.push(depth);
		lines[i] = indentUnit.repeat(depth) + content;
		updateLexicalState(line, depth);
	}

	// Depth of the first line of the statement continued on line idx:
	// walks up past chain links. A link either starts with an operator
	// or ends with one while the line above also ends with one (which
	// tells chain middles apart from statement starts).
	function statementStartDepth(allLines, depths, idx) {
		let s = idx - 1;
		while (s >= 0 && allLines[s].trim() === "") s--;
		while (s >= 0) {
			const t = stripLineComment(allLines[s].trim());
			if (t === "") { s--; continue; }
			if (/^(?:&&|\|\||\?|:)(?![=:])/.test(t)) { s--; continue; }
			if (endsWithOp(t)) {
				let p = s - 1;
				while (p >= 0 && allLines[p].trim() === "") p--;
				if (p >= 0 && endsWithOp(stripLineComment(allLines[p].trim()))) { s = p; continue; }
			}
			break;
		}
		if (s < 0) return null;
		const d = depths[s];
		return d === null || d === undefined ? null : d;
	}

	function endsWithOp(text) {
		return /(&&|\|\||\?|:|[+\-*/%=])$/.test(text) && !/^(?:case|default)\b/.test(text);
	}

	const spacedControlBlocks = addControlBlockSpacing(lines.map(normalizeControlSpacing));
	return addSingleLineArraySpacing(spacedControlBlocks).join(newline);

	// Collapse runs of 2+ spaces after a control header's closing paren
	// (`if (c)  x;` -> `if (c) x;`). Comment-safe: code part only.
	function normalizeControlSpacing(line) {
		let codeEnd = line.length;
		let q = null;
		for (let i = 0; i < line.length - 1; i++) {
			const c = line[i];
			if (q !== null) {
				if (c === "\\") i++;
				else if (c === q) q = null;
			} else if (c === "\"" || c === "'") {
				q = c;
			} else if (c === "/" && line[i + 1] === "/") {
				codeEnd = i;
				break;
			}
		}
		const code = line.slice(0, codeEnd);
		const comment = line.slice(codeEnd);
		return code.replace(/^(\s*)(if|for|while)\b(.*)\)\s{2,}(\S)/, "$1$2$3) $4") + comment;
	}

	function endsWithOperator(allLines, idx) {
		for (let p = idx - 1; p >= 0; p--) {
			const t = allLines[p].trim();
			if (t === "") continue;
			const code = stripLineComment(t);
			return endsWithOp(code);
		}
		return false;
	}

	function stripLineComment(text) {
		let q = null;
		for (let i = 0; i < text.length - 1; i++) {
			const c = text[i];
			if (q !== null) {
				if (c === "\\") i++;
				else if (c === q) q = null;
			} else if (c === "\"" || c === "'") {
				q = c;
			} else if (c === "/" && text[i + 1] === "/") {
				return text.slice(0, i).trimEnd();
			}
		}
		return text.trimEnd();
	}

	function updateLexicalState(line, depth) {
		for (let i = 0; i < line.length; i++) {
			const char = line[i];
			const next = line[i + 1];

			if (quote !== null) {
				if (escaped) {
					escaped = false;
				} else if (char === "\\") {
					escaped = true;
				} else if (char === quote) {
					quote = null;
				}
				continue;
			}

			if (inBlockComment) {
				if (char === "*" && next === "/") {
					inBlockComment = false;
					i++;
				}
				continue;
			}

			if (char === "/" && next === "/") break;
			if (char === "/" && next === "*") {
				inBlockComment = true;
				i++;
				continue;
			}
			if (char === "\"" || char === "'") {
				quote = char;
				escaped = false;
				continue;
			}

			if (char === "(" || char === "[" || char === "{") {
				delimiterStack.push({ ch: char, block: char === "{", stmtDepth: depth });
			} else if (char === ")" || char === "]" || char === "}") {
				const expected = char === ")" ? "(" : char === "]" ? "[" : "{";
				if (delimiterStack[delimiterStack.length - 1]?.ch === expected) {
					delimiterStack.pop();
				}
			}
		}
	}
}

function addControlBlockSpacing(lines) {
	const tokens = tokenizeGml(lines);
	const pairs = new Map();
	const stack = [];

	for (let i = 0; i < tokens.length; i++) {
		const value = tokens[i].value;
		if (value === "(" || value === "[" || value === "{") {
			stack.push(i);
			continue;
		}

		const expectedOpen = value === ")" ? "(" : value === "]" ? "[" : value === "}" ? "{" : null;
		if (expectedOpen === null || tokens[stack[stack.length - 1]]?.value !== expectedOpen) {
			continue;
		}

		const openIndex = stack.pop();
		pairs.set(openIndex, i);
	}

	const before = new Set();
	const removeBefore = new Set();
	const after = new Set();
	const removeBlankAfter = new Set();
	const bodyEndByHeader = new Map();
	const openingByClosing = new Map([...pairs].map(([open, close]) => [close, open]));
	// Pass 1: map every control header to its body end first. The else-if
	// chain walk below needs entries of headers that appear later in the
	// token stream (e.g. the `if` in `} else if`), which a single forward
	// pass has not seen yet when the outer `if` is processed.
	for (let i = 0; i < tokens.length; i++) {
		if (tokens[i].value !== "if" && tokens[i].value !== "for" && tokens[i].value !== "while") continue;

		const parenIndex = i + 1;
		const conditionEnd = pairs.get(parenIndex);
		if (tokens[parenIndex]?.value !== "(" || conditionEnd === undefined) continue;

		const bodyIndex = conditionEnd + 1;
		const bodyEnd = pairs.get(bodyIndex);
		if (tokens[bodyIndex]?.value !== "{" || bodyEnd === undefined) continue;
		bodyEndByHeader.set(i, bodyEnd);
	}
	for (let i = 0; i < tokens.length; i++) {
		if (tokens[i].value !== "if" && tokens[i].value !== "for" && tokens[i].value !== "while") continue;

		const bodyEnd = bodyEndByHeader.get(i);
		if (bodyEnd === undefined) continue;

		const isElseIf = tokens[i].value === "if" && tokens[i - 1]?.value === "else";
		const followsIf = isImmediatelyAfterIf(tokens, pairs, openingByClosing, i);
		const followsFunctionHeader = isFunctionHeader(tokens, pairs, i - 1);
		const followsFunctionOrControlOpening = isImmediatelyInsideFunction(tokens, pairs, i - 1) ||
			isImmediatelyInsideControl(tokens, pairs, i - 1);
		const followsComment = hasCommentImmediatelyBefore(lines, tokens[i].line);
		const followsClosingBraceLine = /^\s*}\s*(?:\/\/.*)?$/.test(lines[tokens[i].line - 1] ?? "");
		const followsElseOpeningLine = /^\s*}\s*else\s*\{\s*(?:\/\/.*)?$/.test(lines[tokens[i].line - 1] ?? "");
		if (!isElseIf && !followsIf && !followsFunctionHeader && !followsFunctionOrControlOpening && !followsComment &&
			!followsClosingBraceLine && !followsElseOpeningLine) {
			before.add(tokens[i].line);
		}
		if (followsFunctionOrControlOpening) {
			removeBefore.add(tokens[i].line);
		}

		let finalBodyEnd = bodyEnd;
		let nextIndex = finalBodyEnd + 1;
		while (tokens[nextIndex]?.value === "else") {
			const branchIndex = nextIndex + 1;
			if (tokens[branchIndex]?.value === "if") {
				const branchEnd = bodyEndByHeader.get(branchIndex);
				if (branchEnd === undefined) break;
				finalBodyEnd = branchEnd;
				nextIndex = finalBodyEnd + 1;
				continue;
			}

			if (tokens[branchIndex]?.value === "{") {
				const elseEnd = pairs.get(branchIndex);
				if (elseEnd !== undefined) finalBodyEnd = elseEnd;
			}
			break;
		}

		const bodyEndLine = tokens[finalBodyEnd].line;
		let nextContentLine = bodyEndLine + 1;
		while (nextContentLine < lines.length && lines[nextContentLine].trim() === "") nextContentLine++;
		if (/^\s*}/.test(lines[nextContentLine] ?? "")) {
			removeBlankAfter.add(bodyEndLine);
		} else {
			after.add(bodyEndLine);
		}
	}

	const result = [];
	for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
		if (lines[lineIndex].trim() === "") {
			let previousContentLine = lineIndex - 1;
			while (previousContentLine >= 0 && lines[previousContentLine].trim() === "") previousContentLine--;
			if (removeBlankAfter.has(previousContentLine)) continue;
		}
		if (removeBefore.has(lineIndex) && result[result.length - 1]?.trim() === "") {
			result.pop();
		}
		if (before.has(lineIndex) && lineIndex > 0 && lines[lineIndex - 1].trim() !== "") {
			if (result[result.length - 1] !== "") result.push("");
		}

		result.push(lines[lineIndex]);

		if (after.has(lineIndex) && lineIndex < lines.length - 1 && lines[lineIndex + 1].trim() !== "") {
			if (result[result.length - 1] !== "") result.push("");
		}
	}

	return result;
}

function isFunctionHeader(tokens, pairs, closeIndex) {
	if (closeIndex < 0 || tokens[closeIndex]?.value !== ")") return false;
	const openIndex = [...pairs.entries()].find(([, end]) => end === closeIndex)?.[0];
	if (openIndex === undefined) return false;
	const functionNameIndex = openIndex - 1;
	return tokens[functionNameIndex]?.type === "word" &&
		tokens[functionNameIndex - 1]?.value === "function";
}

function isImmediatelyInsideFunction(tokens, pairs, openIndex) {
	if (tokens[openIndex]?.value !== "{") return false;
	const closeParenIndex = openIndex - 1;
	return isFunctionHeader(tokens, pairs, closeParenIndex);
}

function isImmediatelyInsideControl(tokens, pairs, openIndex) {
	if (tokens[openIndex]?.value !== "{") return false;
	const closeParenIndex = openIndex - 1;
	if (tokens[closeParenIndex]?.value !== ")") return false;
	const openParenIndex = [...pairs.entries()].find(([, end]) => end === closeParenIndex)?.[0];
	return openParenIndex !== undefined &&
		["if", "for", "while"].includes(tokens[openParenIndex - 1]?.value);
}

function isImmediatelyAfterIf(tokens, pairs, openingByClosing, ifIndex) {
	const previousIndex = ifIndex - 1;
	if (tokens[previousIndex]?.value !== "}") return false;
	const bodyOpen = openingByClosing.get(previousIndex);
	if (bodyOpen === undefined) return false;
	const conditionClose = bodyOpen - 1;
	if (tokens[conditionClose]?.value !== ")") return false;
	const conditionOpen = [...pairs.entries()].find(([, end]) => end === conditionClose)?.[0];
	return conditionOpen !== undefined && tokens[conditionOpen - 1]?.value === "if";
}

function hasCommentImmediatelyBefore(lines, lineIndex) {
	let cursor = lineIndex - 1;
	while (cursor >= 0 && lines[cursor].trim() === "") cursor--;
	if (cursor < 0) return false;

	const line = lines[cursor].trim();
	if (line.startsWith("//") || line.startsWith("/*") || line.endsWith("*/") || line.startsWith("*")) {
		return true;
	}
	return false;
}

function tokenizeGml(lines) {
	const tokens = [];
	let inBlockComment = false;
	let quote = null;
	let escaped = false;

	for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
		const line = lines[lineIndex];
		if (line.trimStart().startsWith("#")) continue;

		for (let i = 0; i < line.length; i++) {
			const char = line[i];
			const next = line[i + 1];

			if (quote !== null) {
				if (escaped) escaped = false;
				else if (char === "\\") escaped = true;
				else if (char === quote) quote = null;
				continue;
			}

			if (inBlockComment) {
				if (char === "*" && next === "/") {
					inBlockComment = false;
					i++;
				}
				continue;
			}

			if (char === "/" && next === "/") break;
			if (char === "/" && next === "*") {
				inBlockComment = true;
				i++;
				continue;
			}
			if (char === "\"" || char === "'") {
				quote = char;
				escaped = false;
				tokens.push({ value: "<string>", type: "string", line: lineIndex, start: i, end: i + 1 });
				continue;
			}

			if (/[A-Za-z_]/.test(char)) {
				const start = i;
				while (i + 1 < line.length && /[A-Za-z0-9_]/.test(line[i + 1])) i++;
				tokens.push({ value: line.slice(start, i + 1), type: "word", line: lineIndex, start, end: i + 1 });
				continue;
			}
			if (/[0-9]/.test(char)) {
				const start = i;
				while (i + 1 < line.length && /[A-Za-z0-9_.]/.test(line[i + 1])) i++;
				tokens.push({ value: line.slice(start, i + 1), type: "number", line: lineIndex, start, end: i + 1 });
				continue;
			}

			if (!/\s/.test(char)) {
				tokens.push({ value: char, type: "symbol", line: lineIndex, start: i, end: i + 1 });
			}
		}
	}

	return tokens;
}

function addSingleLineArraySpacing(lines) {
	const tokens = tokenizeGml(lines);
	const pairs = new Map();
	const stack = [];

	for (let i = 0; i < tokens.length; i++) {
		const value = tokens[i].value;
		if (value === "[") {
			stack.push(i);
		} else if (value === "]" && tokens[stack[stack.length - 1]]?.value === "[") {
			const openIndex = stack.pop();
			pairs.set(openIndex, i);
		}
	}

	const arrayPairsByLine = new Map();
	const prefixKeywords = new Set([
		"case", "delete", "do", "else", "for", "globalvar", "if", "new",
		"not", "repeat", "return", "throw", "typeof", "until", "var", "while",
		"with", "yield",
	]);
	for (const [openIndex, closeIndex] of pairs) {
		const open = tokens[openIndex];
		const close = tokens[closeIndex];
		if (open.line !== close.line) continue;

		const inside = tokens.slice(openIndex + 1, closeIndex);
		if (inside.length === 0 || ["$", "?", "#", "|", "@"].includes(inside[0].value)) continue;

		const previous = tokens[openIndex - 1];
		const followsExpression = previous && (
			previous.type === "string" ||
			previous.type === "number" ||
			(previous.type === "word" && !prefixKeywords.has(previous.value)) ||
			[")", "]", "}"].includes(previous.value)
		);
		if (followsExpression) continue;

		if (!arrayPairsByLine.has(open.line)) arrayPairsByLine.set(open.line, new Map());
		arrayPairsByLine.get(open.line).set(open.start, close.start);
	}

	return lines.map((line, lineIndex) => {
		const pairsOnLine = arrayPairsByLine.get(lineIndex);
		if (!pairsOnLine) return line;

		const closes = new Set(pairsOnLine.values());
		let output = "";
		for (let i = 0; i < line.length; ) {
			if (pairsOnLine.has(i)) {
				const close = pairsOnLine.get(i);
				const inner = line.slice(i + 1, close);
				if (inner.trim().length === 0) {
					output += line.slice(i, close + 1);
					i = close + 1;
					continue;
				}

				output += "[ ";
				let next = i + 1;
				while (next < close && /\s/.test(line[next])) next++;
				if (closes.has(next)) {
					output = output.replace(/[ \t]+$/, "");
					output += " ";
				}
				i = next;
				continue;
			}

			if (closes.has(i)) {
				output = output.replace(/[ \t]+$/, "");
				output += " ]";
				i++;
				continue;
			}
			output += line[i];
			i++;
		}
		return output;
	});
}

const files = collectGmlFiles(projectRoot).sort();
const skipCompact = process.argv.includes("--no-compact");
let changed = 0;

for (const file of files) {
	const original = fs.readFileSync(file, "utf8");
	const formatted = formatIndentation(skipCompact ? original : collapseSingleStatements(original));
	if (formatted !== original) {
		fs.writeFileSync(file, formatted, "utf8");
		changed++;
		console.log(`Formatted ${path.relative(projectRoot, file)}`);
	}
}

console.log(`Formatted ${changed} of ${files.length} GML files.`);

// Collapse single-statement braced if/for/while blocks onto one line
// (`if (c) {\n  stmt;\n}` -> `if (c) stmt;`), dropping a directly
// following blank line. Whitespace-only change; runs before indentation.
function collapseSingleStatements(source) {
	const newline = source.includes("\r\n") ? "\r\n" : "\n";
	let lines = source.split(/\r\n|\n/);
	let changed = true;
	let pass = 0;
	while (changed && pass < 10) {
		changed = false;
		pass++;
		const out = [];
		for (let i = 0; i < lines.length; i++) {
			const a = lines[i], b = lines[i + 1], c = lines[i + 2];
			const m = /^([ \t]*)(if|for|while)\b(.*)\{\s*$/.exec(a);
			let done = false;
			if (m && b !== undefined && c !== undefined) {
				const indent = m[1], kw = m[2], cond = m[3];
				const bt = b.replace(/^\s+/, "");
				const condStripped = stripForCollapse(cond);
				const stmtStripped = stripForCollapse(b);
				if (bt !== "" && bt[0] !== "#" &&
					/;\s*$/.test(bt) &&
					condStripped.indexOf("{") < 0 && condStripped.indexOf("}") < 0 &&
					stmtStripped.indexOf("{") < 0 && stmtStripped.indexOf("}") < 0 &&
					!hasInlineComment(a) && !hasInlineComment(b) &&
					/^[ \t]*\}\s*$/.test(c)) {
					const d = lines[i + 3] || "";
					if (!/^\s*else\b/.test(d)) {
						const opens = (condStripped.match(/\(/g) || []).length;
						const closes = (condStripped.match(/\)/g) || []).length;
						if (opens === closes) {
							out.push(indent + kw + cond.replace(/\s+$/, "") + " " + bt);
							let j = i + 3;
							while (j < lines.length && lines[j].trim() === "") j++;
							i = j - 1;
							changed = true;
							done = true;
						}
					}
				}
			}
			if (!done) out.push(a);
		}
		lines = out;
	}
	return lines.join(newline);
}

function stripForCollapse(line) {
	let out = "", q = null, esc = false;
	for (let i = 0; i < line.length; i++) {
		const c = line[i];
		if (q) {
			if (esc) esc = false;
			else if (c === "\\") esc = true;
			else if (c === q) q = null;
		} else if (c === "\"" || c === "'") {
			q = c;
		} else {
			out += c;
		}
	}
	return out;
}

function hasInlineComment(line) {
	let q = null;
	for (let i = 0; i < line.length - 1; i++) {
		const c = line[i];
		if (q !== null) {
			if (c === "\\") i++;
			else if (c === q) q = null;
		} else if (c === "\"" || c === "'") {
			q = c;
		} else if (c === "/" && line[i + 1] === "/") {
			return true;
		}
	}
	return false;
}
