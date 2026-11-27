#!/usr/bin/env python3
"""Builds the Pasr account mails (Supabase Auth) in the Pasr house style and writes templates.json for the
Supabase Management API (workflow Backend). Run: python3 supabase/templates/build.py

Links never go to …supabase.co: they go to pasr.nl/bevestigen/ with the token_hash, and that page confirms only
after a tap (link scanners in mail programs open links in advance and would otherwise use up the one-time link).
Mails greet with the first name when the user gave one ("Hoi Léon,"). Pasr is Dutch only.
"""
import html
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SITE = "https://pasr.nl"
INK, PANEL, IRIS, CORAL, MINT, TEXT, MUTED = "#0A0B10", "#15171F", "#6A5CFF", "#FF6B57", "#2ED3A6", "#E9EAF0", "#9A9DAB"
FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"

TEMPLATES = {
    "confirmation": dict(
        type="signup",
        subject="Welkom bij Pasr · Bevestig je e-mailadres",
        eyebrow="Account",
        title="Bevestig je e-mailadres",
        intro="Fijn dat je een Pasr-account maakt. Bevestig je e-mailadres, dan staan al je klantenkaarten en "
              "vouchers veilig in je account en heb je ze op al je apparaten.",
        button="E-mailadres bevestigen",
        note="Heb jij geen Pasr-account gemaakt? Dan kun je deze mail negeren; zonder bevestiging wordt het account "
             "binnen 48 uur verwijderd.",
    ),
    "recovery": dict(
        type="recovery",
        subject="Pasr · Nieuw wachtwoord instellen",
        eyebrow="Wachtwoord",
        title="Nieuw wachtwoord instellen",
        intro="We kregen een verzoek om het wachtwoord van je Pasr-account te wijzigen. Tik op de knop om een "
              "nieuw wachtwoord te kiezen.",
        button="Nieuw wachtwoord kiezen",
        note="Heb jij dit niet gevraagd? Dan hoef je niets te doen: je wachtwoord blijft zoals het is.",
    ),
    "email_change": dict(
        type="email_change",
        subject="Pasr · Bevestig je nieuwe e-mailadres",
        eyebrow="Account",
        title="Bevestig je nieuwe e-mailadres",
        intro="Je wilt het e-mailadres van je Pasr-account wijzigen naar <b style=\"color:#ffffff\">{{ .NewEmail }}</b>. "
              "Bevestig dat met de knop hieronder.",
        button="Nieuw e-mailadres bevestigen",
        note="Heb jij dit niet gevraagd? Negeer deze mail; je e-mailadres blijft dan zoals het is.",
    ),
    "magic_link": dict(
        type="magiclink",
        subject="Pasr · Je inloglink",
        eyebrow="Inloggen",
        title="Inloggen bij Pasr",
        intro="Tik op de knop om in te loggen bij je Pasr-account. De link werkt één keer en is een uur geldig.",
        button="Inloggen",
        note="Heb jij niet gevraagd om in te loggen? Dan kun je deze mail negeren.",
    ),
}


def mail(t):
    link = f"{SITE}/bevestigen/?token_hash={{{{ .TokenHash }}}}&amp;type={t['type']}"
    logo = (f'<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>'
            f'<td style="width:40px;vertical-align:middle"><img src="{SITE}/assets/mail-icon.png" width="40" height="40" alt="Pasr" '
            f'style="display:block;width:40px;height:40px;border:0;border-radius:9px;color:#ffffff;font-size:12px"></td>'
            f'<td style="padding-left:10px;font-size:26px;font-weight:800;letter-spacing:-0.5px;color:#ffffff;font-family:{FONT}">pasr</td>'
            f'</tr></table>')
    return f"""<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><title>{html.escape(t['subject'])}</title></head>
<body style="margin:0;padding:0;background:{INK}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:{INK}">{html.escape(t['title'])}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{INK}" style="background:{INK}"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;font-family:{FONT}">
<tr><td style="padding:0 4px 22px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle">{logo}</td>
<td align="right" style="vertical-align:middle;font-size:13px;font-weight:700;color:{MUTED};letter-spacing:.3px">{t['eyebrow']}</td>
</tr></table></td></tr>
<tr><td bgcolor="{PANEL}" style="background:{PANEL};border-radius:18px;padding:32px 30px 30px">
<div style="height:6px;width:64px;border-radius:3px;background:{IRIS};font-size:0;line-height:0;margin:0 0 22px">&nbsp;</div>
<h1 style="margin:0 0 12px;font-size:24px;line-height:30px;font-weight:800;color:#ffffff">{t['title']}</h1>
{{{{ if .Data.first_name }}}}<p style="margin:0 0 12px;font-size:15px;line-height:23px;font-weight:600;color:#ffffff">Hoi {{{{ .Data.first_name }}}},</p>{{{{ end }}}}
<p style="margin:0;font-size:15px;line-height:23px;color:{TEXT}">{t['intro']}</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 0"><tr><td align="center" bgcolor="{IRIS}" style="border-radius:12px;background:{IRIS}">
<a href="{link}" style="display:inline-block;padding:14px 28px;font-family:{FONT};font-size:16px;font-weight:700;line-height:20px;color:#ffffff;text-decoration:none;border-radius:12px">{t['button']}</a></td></tr></table>
<p style="margin:22px 0 0;font-size:13px;line-height:20px;color:{MUTED}">Werkt de knop niet? Kopieer dan deze link in je browser:<br>
<a href="{link}" style="color:{IRIS};word-break:break-all">{link}</a></p>
<div style="height:1px;background:#262935;margin:24px 0 18px;font-size:0;line-height:0">&nbsp;</div>
<p style="margin:0;font-size:13px;line-height:20px;color:{MUTED}">{t['note']}</p>
</td></tr>
<tr><td style="padding:22px 6px 0;font-size:12px;line-height:18px;color:{MUTED}">
Je krijgt deze mail omdat dit e-mailadres is gebruikt voor een Pasr-account. Pasr is de gratis app voor je klantenkaarten en vouchers.<br>
<a href="{SITE}" style="color:{MUTED}">pasr.nl</a> · <a href="{SITE}/privacy/" style="color:{MUTED}">Privacy</a> · <a href="{SITE}/support/" style="color:{MUTED}">Hulp</a>
</td></tr>
</table></td></tr></table>
</body></html>"""


INVITE = dict(
    subject="{{FROM}} nodigt je uit voor een gedeelde Pasr",
    eyebrow="Gedeelde Pasr",
    title="Uitnodiging voor &ldquo;{{GROUP}}&rdquo;",
    intro="{{FROM}} wil klantenkaarten met je delen in de gedeelde Pasr <b style=\"color:#ffffff\">{{GROUP}}</b>. "
          "Open Pasr en log in met dit e-mailadres, of maak gratis een account. Daarna kun je de uitnodiging accepteren.",
    button="Uitnodiging bekijken",
    note="Ken je deze persoon niet? Dan kun je deze mail negeren. De uitnodiging verloopt na 14 dagen.",
)


def invite_mail():
    """Mail voor een uitnodiging (functie group-invite). {{FROM}} en {{GROUP}} vult de functie in (HTML-veilig)."""
    import re
    body = mail(dict(INVITE, type="invite"))
    body = body.replace(f"{SITE}/bevestigen/?token_hash={{{{ .TokenHash }}}}&amp;type=invite", f"{SITE}/uitnodiging/")
    body = re.sub(r"\{\{ if \.Data\.first_name \}\}.*?\{\{ end \}\}", "", body, flags=re.S)
    body = body.replace("Je krijgt deze mail omdat dit e-mailadres is gebruikt voor een Pasr-account.",
                        "Je krijgt deze mail omdat {{FROM}} je heeft uitgenodigd voor een gedeelde Pasr.")
    return body


def reminder_mail():
    """Mail met herinneringen (functie reminder-mail). De functie vult {{TITLE}}, {{PREHEADER}}, {{GREETING}}, {{INTRO}},
    {{ROWS}} (tabelregels) en {{STOP}} (afmeldlink) in, allemaal HTML-veilig."""
    rows_block = (f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" '
                  f'style="margin:22px 0 0;border-collapse:separate;border-spacing:0 8px">{{{{ROWS}}}}</table>')
    return f"""<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><title>{{{{TITLE}}}}</title></head>
<body style="margin:0;padding:0;background:{INK}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:{INK}">{{{{PREHEADER}}}}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{INK}" style="background:{INK}"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;font-family:{FONT}">
<tr><td style="padding:0 4px 22px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="width:40px;vertical-align:middle"><img src="{SITE}/assets/mail-icon.png" width="40" height="40" alt="Pasr" style="display:block;width:40px;height:40px;border:0;border-radius:9px;color:#ffffff;font-size:12px"></td>
<td style="padding-left:10px;font-size:26px;font-weight:800;letter-spacing:-0.5px;color:#ffffff;font-family:{FONT}">pasr</td>
</tr></table></td>
<td align="right" style="vertical-align:middle;font-size:13px;font-weight:700;color:{MUTED};letter-spacing:.3px">Herinnering</td>
</tr></table></td></tr>
<tr><td bgcolor="{PANEL}" style="background:{PANEL};border-radius:18px;padding:32px 30px 30px">
<div style="height:6px;width:64px;border-radius:3px;background:{MINT};font-size:0;line-height:0;margin:0 0 22px">&nbsp;</div>
<h1 style="margin:0 0 12px;font-size:24px;line-height:30px;font-weight:800;color:#ffffff">{{{{TITLE}}}}</h1>
{{{{GREETING}}}}
<p style="margin:0;font-size:15px;line-height:23px;color:{TEXT}">{{{{INTRO}}}}</p>
{rows_block}
<div style="height:1px;background:#262935;margin:24px 0 18px;font-size:0;line-height:0">&nbsp;</div>
<p style="margin:0;font-size:13px;line-height:20px;color:{MUTED}">Open Pasr om je kaart te tonen of je tegoed bij te werken. Pasr kent alleen het tegoed dat je zelf bijhoudt; de winkel geeft niets door.</p>
</td></tr>
<tr><td style="padding:22px 6px 0;font-size:12px;line-height:18px;color:{MUTED}">
Je krijgt deze mail omdat je in Pasr herinneringen per e-mail hebt aangezet. Uitzetten kan in Pasr › Instellingen › Meldingen, of <a href="{{{{STOP}}}}" style="color:{MUTED}">meld je hier af</a>.<br>
<a href="{SITE}" style="color:{MUTED}">pasr.nl</a> · <a href="{SITE}/privacy/" style="color:{MUTED}">Privacy</a> · <a href="{SITE}/support/" style="color:{MUTED}">Hulp</a>
</td></tr>
</table></td></tr></table>
</body></html>"""


REMINDER_ROW = (f'<tr><td bgcolor="#1C1F29" style="background:#1C1F29;border-radius:12px;padding:14px 16px;font-family:{FONT}">'
                f'<div style="font-size:15px;line-height:21px;font-weight:700;color:#ffffff">{{{{STORE}}}}</div>'
                f'<div style="font-size:13px;line-height:19px;color:{MUTED}">{{{{DETAIL}}}}</div></td>'
                f'<td bgcolor="#1C1F29" align="right" style="background:#1C1F29;border-radius:12px;padding:14px 16px;'
                f'white-space:nowrap;font-family:{FONT};font-size:15px;font-weight:800;color:{{{{COLOR}}}}">{{{{VALUE}}}}</td></tr>')



def community_mail():
    """Mail bij gezamenlijke acties van Pasr Zakelijk (functie community-mail). De functie vult {{EYEBROW}}, {{TITLE}},
    {{PREHEADER}}, {{ACCENT}}, {{INTRO}}, {{ROWS}} (regels van ROW), {{BUTTON}}, {{LINK}} en {{NOTE}} in, allemaal
    HTML-veilig. Dezelfde donkere Pasr-huisstijl als de accountmails: mail-icoon, kaart, knop en voet."""
    rows_block = (f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" '
                  f'style="margin:22px 0 0;border-collapse:separate;border-spacing:0 8px">{{{{ROWS}}}}</table>')
    return f"""<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><title>{{{{TITLE}}}}</title></head>
<body style="margin:0;padding:0;background:{INK}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:{INK}">{{{{PREHEADER}}}}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{INK}" style="background:{INK}"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;font-family:{FONT}">
<tr><td style="padding:0 4px 22px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="width:40px;vertical-align:middle"><img src="{SITE}/assets/mail-icon.png" width="40" height="40" alt="Pasr" style="display:block;width:40px;height:40px;border:0;border-radius:9px;color:#ffffff;font-size:12px"></td>
<td style="padding-left:10px;font-size:26px;font-weight:800;letter-spacing:-0.5px;color:#ffffff;font-family:{FONT}">pasr</td>
</tr></table></td>
<td align="right" style="vertical-align:middle;font-size:13px;font-weight:700;color:{MUTED};letter-spacing:.3px">{{{{EYEBROW}}}}</td>
</tr></table></td></tr>
<tr><td bgcolor="{PANEL}" style="background:{PANEL};border-radius:18px;padding:32px 30px 30px">
<div style="height:6px;width:64px;border-radius:3px;background:{{{{ACCENT}}}};font-size:0;line-height:0;margin:0 0 22px">&nbsp;</div>
<h1 style="margin:0 0 12px;font-size:24px;line-height:30px;font-weight:800;color:#ffffff">{{{{TITLE}}}}</h1>
<p style="margin:0;font-size:15px;line-height:23px;color:{TEXT}">{{{{INTRO}}}}</p>
{rows_block}
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:26px 0 0"><tr><td align="center" bgcolor="{IRIS}" style="border-radius:12px;background:{IRIS}">
<a href="{{{{LINK}}}}" style="display:inline-block;padding:14px 28px;font-family:{FONT};font-size:16px;font-weight:700;line-height:20px;color:#ffffff;text-decoration:none;border-radius:12px">{{{{BUTTON}}}}</a></td></tr></table>
<p style="margin:22px 0 0;font-size:13px;line-height:20px;color:{MUTED}">Werkt de knop niet? Kopieer dan deze link in je browser:<br>
<a href="{{{{LINK}}}}" style="color:{IRIS};word-break:break-all">{{{{LINK}}}}</a></p>
<div style="height:1px;background:#262935;margin:24px 0 18px;font-size:0;line-height:0">&nbsp;</div>
<p style="margin:0;font-size:13px;line-height:20px;color:{MUTED}">{{{{NOTE}}}}</p>
</td></tr>
<tr><td style="padding:22px 6px 0;font-size:12px;line-height:18px;color:{MUTED}">
Je krijgt deze mail over een gezamenlijke actie in Pasr Zakelijk, de gratis digitale stempelkaart voor ondernemers. Er worden geen klantgegevens tussen zaken gedeeld.<br>
<a href="{SITE}/zakelijk/" style="color:{MUTED}">pasr.nl/zakelijk</a> · <a href="{SITE}/privacy/" style="color:{MUTED}">Privacy</a> · <a href="{SITE}/support/" style="color:{MUTED}">Hulp</a>
</td></tr>
</table></td></tr></table>
</body></html>"""


COMMUNITY_ROW = (f'<tr><td bgcolor="#1C1F29" style="background:#1C1F29;border-radius:12px;padding:12px 16px;font-family:{FONT};'
                 f'font-size:13px;line-height:19px;color:{MUTED};width:120px;vertical-align:top">{{{{LABEL}}}}</td>'
                 f'<td bgcolor="#1C1F29" style="background:#1C1F29;border-radius:12px;padding:12px 16px;font-family:{FONT};'
                 f'font-size:15px;line-height:21px;font-weight:700;color:#ffffff">{{{{VALUE}}}}</td></tr>')


def ticket_mail():
    """Mail bij tickets van een event (functie event-mail): bevestiging, herinnering, wijziging, afgelast en plek vrij.
    De functie vult {{EYEBROW}}, {{TITLE}}, {{PREHEADER}}, {{ACCENT}}, {{INTRO}}, {{EVCOLOR}}, {{EVTEXT}}, {{EVBUSINESS}},
    {{EVNAME}}, {{EVWHEN}}, {{ROWS}} (regels van ROW), {{TICKETS}} (regels van TICKET), {{BADGE}} (de knop "Voeg toe aan
    Pasr" of leeg), {{NOTE}} en {{EXTRA}} in, allemaal HTML-veilig. Zelfde donkere Pasr-huisstijl als de andere mails."""
    rows_block = (f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" '
                  f'style="margin:18px 0 0;border-collapse:separate;border-spacing:0 8px">{{{{ROWS}}}}</table>')
    return f"""<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark"><meta name="supported-color-schemes" content="dark"><title>{{{{TITLE}}}}</title></head>
<body style="margin:0;padding:0;background:{INK}">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:{INK}">{{{{PREHEADER}}}}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="{INK}" style="background:{INK}"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;font-family:{FONT}">
<tr><td style="padding:0 4px 22px"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="vertical-align:middle"><table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
<td style="width:40px;vertical-align:middle"><img src="{SITE}/assets/mail-icon.png" width="40" height="40" alt="Pasr" style="display:block;width:40px;height:40px;border:0;border-radius:9px;color:#ffffff;font-size:12px"></td>
<td style="padding-left:10px;font-size:26px;font-weight:800;letter-spacing:-0.5px;color:#ffffff;font-family:{FONT}">pasr</td>
</tr></table></td>
<td align="right" style="vertical-align:middle;font-size:13px;font-weight:700;color:{MUTED};letter-spacing:.3px">{{{{EYEBROW}}}}</td>
</tr></table></td></tr>
<tr><td bgcolor="{PANEL}" style="background:{PANEL};border-radius:18px;padding:32px 30px 30px">
<div style="height:6px;width:64px;border-radius:3px;background:{{{{ACCENT}}}};font-size:0;line-height:0;margin:0 0 22px">&nbsp;</div>
<h1 style="margin:0 0 12px;font-size:24px;line-height:30px;font-weight:800;color:#ffffff">{{{{TITLE}}}}</h1>
<p style="margin:0;font-size:15px;line-height:23px;color:{TEXT}">{{{{INTRO}}}}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0 0"><tr>
<td bgcolor="{{{{EVCOLOR}}}}" style="background:{{{{EVCOLOR}}}};border-radius:14px;padding:18px 20px;font-family:{FONT}">
<div style="font-size:12px;line-height:16px;font-weight:700;color:{{{{EVTEXT}}}};opacity:.85">{{{{EVBUSINESS}}}}</div>
<div style="font-size:22px;line-height:28px;font-weight:800;color:{{{{EVTEXT}}}};margin-top:2px">{{{{EVNAME}}}}</div>
<div style="font-size:14px;line-height:20px;font-weight:600;color:{{{{EVTEXT}}}};margin-top:6px">{{{{EVWHEN}}}}</div>
</td></tr></table>
{rows_block}
{{{{TICKETS}}}}
{{{{BADGE}}}}
{{{{EXTRA}}}}
<div style="height:1px;background:#262935;margin:24px 0 18px;font-size:0;line-height:0">&nbsp;</div>
<p style="margin:0;font-size:13px;line-height:20px;color:{MUTED}">{{{{NOTE}}}}</p>
</td></tr>
<tr><td style="padding:22px 6px 0;font-size:12px;line-height:18px;color:{MUTED}">
Je krijgt deze mail omdat je je met dit e-mailadres hebt aangemeld voor een event via Pasr. Je gegevens gaan alleen naar de organisator van dit event en worden na het event gewist.<br>
<a href="{SITE}/" style="color:{MUTED}">pasr.nl</a> · <a href="{SITE}/privacy/" style="color:{MUTED}">Privacy</a> · <a href="{SITE}/support/" style="color:{MUTED}">Hulp</a>
</td></tr>
</table></td></tr></table>
</body></html>"""


# Eén ticket: QR-code (inline afbeelding, cid) met soort, volgnummer en de code eronder.
TICKET_ROW = (f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:14px 0 0">'
              f'<tr><td width="132" style="width:132px;vertical-align:top"><table role="presentation" cellpadding="0" cellspacing="0" border="0">'
              f'<tr><td bgcolor="#ffffff" style="background:#ffffff;border-radius:12px;padding:8px">'
              f'<img src="{{{{QR}}}}" width="112" height="112" alt="QR-code van je ticket" style="display:block;width:112px;height:112px;border:0">'
              f'</td></tr></table></td>'
              f'<td style="vertical-align:middle;padding-left:14px;font-family:{FONT}">'
              f'<div style="font-size:15px;line-height:21px;font-weight:700;color:#ffffff">{{{{LABEL}}}}</div>'
              f'<div style="font-size:13px;line-height:19px;color:{MUTED};margin-top:2px">{{{{SUB}}}}</div>'
              f'<div style="font-size:13px;line-height:19px;color:{TEXT};margin-top:6px;font-family:Menlo,Consolas,monospace;letter-spacing:1px">{{{{CODE}}}}</div>'
              f'</td></tr></table>')
# De officiële knop "Voeg toe aan Pasr" (PNG, werkt in alle mailprogramma's) met de add-link van het ticket.
TICKET_BADGE = (f'<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0 0"><tr>'
                f'<td><a href="{{{{LINK}}}}" style="display:inline-block;text-decoration:none">'
                f'<img src="{SITE}/badge/nl/zwart.png" width="150" height="52" alt="Voeg toe aan Pasr" '
                f'style="display:block;width:150px;height:52px;border:0;border-radius:10px;background:#ffffff"></a></td></tr></table>'
                f'<p style="margin:10px 0 0;font-size:13px;line-height:20px;color:{MUTED}">Met Pasr heb je je tickets offline bij de hand, '
                f'met een herinnering de dag ervoor. Werkt de knop niet? <a href="{{{{LINK}}}}" style="color:{IRIS};word-break:break-all">Open je ticket</a>.</p>')


def main():
    out = HERE.parent / "functions" / "reminder-mail" / "template.ts"
    out.parent.mkdir(exist_ok=True)
    out.write_text("// Gemaakt door supabase/templates/build.py (niet met de hand wijzigen).\n"
                   f"export const HTML = {json.dumps(reminder_mail(), ensure_ascii=False)};\n"
                   f"export const ROW = {json.dumps(REMINDER_ROW, ensure_ascii=False)};\n"
                   f"export const MINT = {json.dumps(MINT)};\nexport const CORAL = {json.dumps(CORAL)};\n")
    out = HERE.parent / "functions" / "group-invite" / "template.ts"
    out.write_text("// Gemaakt door supabase/templates/build.py (niet met de hand wijzigen).\n"
                   f"export const SUBJECT = {json.dumps(INVITE['subject'], ensure_ascii=False)};\n"
                   f"export const HTML = {json.dumps(invite_mail(), ensure_ascii=False)};\n")
    out = HERE.parent / "functions" / "community-mail" / "template.ts"
    out.parent.mkdir(exist_ok=True)
    out.write_text("// Gemaakt door supabase/templates/build.py (niet met de hand wijzigen).\n"
                   f"export const HTML = {json.dumps(community_mail(), ensure_ascii=False)};\n"
                   f"export const ROW = {json.dumps(COMMUNITY_ROW, ensure_ascii=False)};\n"
                   f"export const IRIS = {json.dumps(IRIS)};\nexport const MINT = {json.dumps(MINT)};\n"
                   f"export const CORAL = {json.dumps(CORAL)};\n")
    out = HERE.parent / "functions" / "event-mail" / "template.ts"
    out.parent.mkdir(exist_ok=True)
    out.write_text("// Gemaakt door supabase/templates/build.py (niet met de hand wijzigen).\n"
                   f"export const HTML = {json.dumps(ticket_mail(), ensure_ascii=False)};\n"
                   f"export const ROW = {json.dumps(COMMUNITY_ROW, ensure_ascii=False)};\n"
                   f"export const TICKET = {json.dumps(TICKET_ROW, ensure_ascii=False)};\n"
                   f"export const BADGE = {json.dumps(TICKET_BADGE, ensure_ascii=False)};\n"
                   f"export const IRIS = {json.dumps(IRIS)};\nexport const MINT = {json.dumps(MINT)};\n"
                   f"export const CORAL = {json.dumps(CORAL)};\n")
    cfg = {}
    for key, t in TEMPLATES.items():
        body = mail(t)
        (HERE / f"{key}.html").write_text(body)
        cfg[f"mailer_subjects_{key}"] = t["subject"]
        cfg[f"mailer_templates_{key}_content"] = body
    (HERE / "templates.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=1) + "\n")
    print("templates.json:", ", ".join(TEMPLATES))


if __name__ == "__main__":
    main()
