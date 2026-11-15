"""Locate KDL v1 nodes without rewriting comments, values or unrelated settings.

Niri remains the validator. This scanner supplies source ranges for narrow edits.
"""
from dataclasses import dataclass, field
import json
import re

@dataclass
class Token:
    text: str
    start: int
    end: int

@dataclass
class Node:
    name: str
    start: int
    end: int
    name_end: int
    header: list
    children: list = field(default_factory=list)
    opening: int | None = None
    closing: int | None = None


def value(token):
    text = token.text
    if text.startswith('"'):
        return json.loads(text)
    raw = re.fullmatch(r'r(#+)?"(.*)"\1', text, re.S)
    if raw:
        return raw[2]
    if text.startswith('r"') and text.endswith('"'):
        return text[2:-1]
    return text


def tokens(text):
    result, i = [], 0
    while i < len(text):
        start = i
        if text[i] in ' \t\r':
            i += 1
        elif text.startswith('//', i):
            end = text.find('\n', i)
            i = len(text) if end < 0 else end
        elif text.startswith('/*', i):
            depth, i = 1, i + 2
            while depth and i < len(text):
                if text.startswith('/*', i): depth, i = depth + 1, i + 2
                elif text.startswith('*/', i): depth, i = depth - 1, i + 2
                else: i += 1
            if depth: raise ValueError('Unclosed KDL comment')
        elif text[i] == '\\':
            # Escaped newline (possibly with whitespace and a line comment).
            i += 1
            while i < len(text) and text[i] in ' \t\r': i += 1
            if text.startswith('//', i):
                end = text.find('\n', i)
                i = len(text) if end < 0 else end
            if i >= len(text) or text[i] != '\n': raise ValueError('Invalid KDL continuation')
            i += 1
        elif text[i] == '"' or re.match(r'r#*"', text[i:]):
            raw = re.match(r'r(#*)"', text[i:])
            if raw:
                close = '"' + raw[1]
                end = text.find(close, i + len(raw[0]))
                if end < 0: raise ValueError('Unclosed KDL raw string')
                i = end + len(close)
            else:
                i += 1
                while i < len(text):
                    if text[i] == '\\': i += 2
                    elif text[i] == '"':
                        i += 1
                        break
                    else: i += 1
                else: raise ValueError('Unclosed KDL string')
            result.append(Token(text[start:i], start, i))
        elif text[i] in '{};\n=':
            i += 1
            result.append(Token(text[start:i], start, i))
        elif text.startswith('/-', i):
            i += 2
            result.append(Token('/-', start, i))
        else:
            while i < len(text) and not text[i].isspace() and text[i] not in '{};=' and not text.startswith('//', i) and not text.startswith('/*', i): i += 1
            if i == start: raise ValueError('Unsupported KDL token')
            result.append(Token(text[start:i], start, i))
    return result


def parse(text):
    ts = tokens(text)
    def block(index, nested=False):
        nodes = []
        while index < len(ts):
            token = ts[index]
            if token.text in (';', '\n'):
                index += 1
                continue
            if token.text == '}':
                if not nested: raise ValueError('Unexpected KDL closing brace')
                return nodes, index
            disabled = token.text == '/-'
            if disabled:
                index += 1
                token = ts[index]
            node = Node(value(token), token.start, token.end, token.end, [])
            index += 1
            while index < len(ts) and ts[index].text not in ('{', '}', ';', '\n'):
                node.header.append(ts[index]); index += 1
            if index < len(ts) and ts[index].text == '{':
                node.opening = ts[index].start
                node.children, index = block(index + 1, True)
                if index >= len(ts): raise ValueError('Unclosed KDL block')
                node.closing = ts[index].start
                node.end = ts[index].end
                index += 1
            elif node.header:
                node.end = node.header[-1].end
            if index < len(ts) and ts[index].text in (';', '\n'):
                node.end = ts[index].end; index += 1
            if not disabled:
                nodes.append(node)
        if nested: raise ValueError('Unclosed KDL block')
        return nodes, index
    return block(0)[0]
