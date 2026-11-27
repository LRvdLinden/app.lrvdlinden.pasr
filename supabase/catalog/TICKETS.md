# Evenementtickets

De catalogus bevat sjablonen, geen uitgegeven tickets of verkoopvoorraad. Een gebruiker scant een reeds gekocht ticket of kiest een foto/screenshot met een vaste code. Wisselende/mobile-only codes blijven in de officiële app. Geen voorbeeldcodes in de catalogus.

De vier Drakenboot-varianten zijn afzonderlijke sjablonen. De naam van de gekozen variant gaat mee in de bestaande kaartgegevens. De officiële logo's en kleuren moeten in Beheer worden gecontroleerd en ingesteld; voorlopig wordt een neutrale kleur gebruikt, zonder logo. 

Bronnen: https://www.drakenboot.nl/tickets, https://www.zwartecross.nl/veelgestelde-vragen/, https://www.concertatsea.nl/veelgestelde-vragen/.

Publicatie via de bestaande backend-workflow en seed.py; bestaande records worden niet overschreven. De gebruikersapps lezen gepubliceerde records uit pasr_store_catalog.

## Ticketweergave en huisstijl (1.0.5)

Een ticket ziet er in de apps uit als een eventTicket in Apple Wallet (iOS `TicketFaceView`, Android `TicketFace`) en wordt
in Wallet een echte `eventTicket`-pas (supabase/functions/wallet-pass/passkit.ts, `ticketPass`). De gegevens komen uit de
gids van het sjabloon (pasr_stores.guide), zie `TicketEvent` in supabase/functions/admin/stores.ts:
`event`, `brand`, `date`, `end_date`, `doors`, `ends`, `venue`, `city`, `address`, `ticket_type`, `ticket_note`,
`info_url`, `text_hex`, `label_hex`. In het beheer (web en Pasr Beheer) staan ze bij Soort kaart = Ticket onder "Evenement".
Eerste vulling: guides.json (guides.py, alleen waar de gids nog leeg is).

- Drakenboot 2027 (18 juni 2027, 17:00 – 01:00, Zwitsalpark, Apeldoorn; KIDS t/m 14 jaar): uit het ontwerp van Léon
  ("Drakenboot in Pasr"). Controleren op drakenboot.nl.
- Zwarte Cross 2027: 15 – 18 juli 2027, Festivalterrein De Schans, Heringsaweg, 7137 PH Lichtenvoorde
  (festivalinfo.nl, nog te controleren op zwartecross.nl). Tijden onbekend, dus leeg.
- Concert at SEA 2027: 24 – 26 juni 2027, Brouwersdam (festivalfans.nl, nog te controleren op concertatsea.nl).

Logo en merkkleur: Actions › Logos › Run workflow met "tickets" aangevinkt (`tools/fetch_logos.py --tickets`, zelfde
stappen als de winkellogo's: logo uit de kop van de site, anders Wikimedia/het icoon van de site; kleur uit de
achtergrond van het logo of de theme-color van de site) → supabase/catalog/ticket_brands.json → ticket_brands.py zet
ze in de Backend-workflow in het beheer, alleen waar nog geen logo of nog de neutrale kleur staat. Niets verzonnen: is
er geen logo, dan tonen de apps de initialen van het evenement in de merkkleur.
