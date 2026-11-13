# SPDX-License-Identifier: Apache-2.0
"""Reviewer's 2026-11-13 39-case tokenizer prefixes, retained without scanning."""


def tokenizer_cases(early):
    cases = {
        'comment-abrupt-empty-before-author': '<!doctype html><!-->' + early + '<!-- --><html><head></head>',
        'comment-abrupt-dash-before-author': '<!doctype html><!--->' + early + '<!-- --><html><head></head>',
        'malformed-html-attribute-before-author': '<!doctype html><html data-note=a" >' + early + '<!--" --><head></head>',
        'normal-comment': '<!doctype html><!-- <head> --><html><head></head>',
        'unterminated-comment': '<!doctype html><!-- <head>',
        'unterminated-comment-dashes': '<!doctype html><!-- <head> --',
        'abrupt-comment-empty': '<!doctype html><!--><html><head></head>',
        'abrupt-comment-dash': '<!doctype html><!---><html><head></head>',
        'comment-bang-close': '<!doctype html><!-- <head> --!><html><head></head>',
        'bogus-declaration': '<!doctype html><!foo <head>><html><head></head>',
        'bogus-processing-instruction': '<!doctype html><?foo <head>><html><head></head>',
        'unterminated-bogus-declaration': '<!doctype html><!foo <head',
        'unterminated-processing-instruction': '<!doctype html><?foo <head',
        'template-head-text': '<!doctype html><html><template><head><title>fake</title></head></template><head></head>',
        'noscript-head-text': '<!doctype html><html><noscript><head>fake</head></noscript><head></head>',
        'svg-head-text': '<!doctype html><html><svg><text>&lt;head&gt;</text><head></head></svg><head></head>',
        'math-head-text': '<!doctype html><html><math><mtext>&lt;head&gt;</mtext><head></head></math><head></head>',
        'textarea-head-text': '<!doctype html><html><textarea><head>fake</head></textarea><head></head>',
        'title-head-text': '<!doctype html><html><title><head>fake</head></title><head></head>',
        'uppercase-head-attributes': '<!DOCTYPE html><HTML lang="en"><HEAD data-note="quoted > <head>"></HEAD>',
        'missing-head': '<!doctype html><html>',
        'bom-leading-ascii-space': '\ufeff \t\r\n<!doctype html><html><head></head>',
        'nul-prefix': '\x00<!doctype html><html><head></head>',
        'nul-head-name': '<!doctype html><html><head\x00data-note="nul"></head>',
        'nul-head-attribute': '<!doctype html><html><head data-note="nul\x00"><title>probe</title></head>',
        'nbsp-prefix': '\u00a0<!doctype html><html><head></head>',
        'em-space-head-name': '<!doctype html><html><head\u2003data-note="em"></head>',
        'line-separator-head-name': '<!doctype html><html><head\u2028data-note="ls"></head>',
        'nbsp-html-name': '<!doctype html><html\u00a0data-note="nbsp"><head></head>',
        'vertical-tab-html-name': '<!doctype html><html\vdata-note="vt"><head></head>',
        'malformed-head-attribute-refusal': '<!doctype html><html data-note=a"<head>"><head></head>',
    }
    for keyword in ('PUBLIC', 'SYSTEM'):
        for quote_name, quote in (('single', "'"), ('double', '"')):
            cases['doctype-' + keyword.lower() + '-' + quote_name] = (
                '<!doctype html ' + keyword + ' ' + quote + '<head>' + quote + ' "about:legacy-compat"><html><head></head>')
    cases['doctype-unterminated'] = '<!doctype html PUBLIC "never closes <head'
    cases['later-add-head-node'] = '<!doctype html><html><head><script>const style=document.createElement("style");style.textContent="body{padding:0}";document.head.append(style);console.warn("LATER-HEAD-ADD");</script></head>'
    cases['later-remove-policy'] = '<!doctype html><html><head><script>document.querySelector("[data-bench-csp]").remove();console.warn("LATER-POLICY-REMOVAL");</script></head>'
    cases['later-replace-head'] = '<!doctype html><html><head><script>document.documentElement.replaceChild(document.createElement("head"),document.head);console.warn("LATER-HEAD-REPLACEMENT");</script></head>'
    return cases
