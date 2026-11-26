# Evenementtickets

De catalogus bevat sjablonen, geen uitgegeven tickets of verkoopvoorraad. Een gebruiker scant een reeds gekocht ticket of kiest een foto/screenshot met een vaste code. Wisselende/mobile-only codes blijven in de officiële app. Geen voorbeeldcodes in de catalogus.

De vier Drakenboot-varianten zijn afzonderlijke sjablonen. De naam van de gekozen variant gaat mee in de bestaande kaartgegevens. De officiële logo's en kleuren moeten in Beheer worden gecontroleerd en ingesteld; voorlopig wordt een neutrale kleur gebruikt, zonder logo. 

Bronnen: https://www.drakenboot.nl/tickets, https://www.zwartecross.nl/veelgestelde-vragen/, https://www.concertatsea.nl/veelgestelde-vragen/.

Publicatie via de bestaande backend-workflow en seed.py; bestaande records worden niet overschreven. De gebruikersapps lezen gepubliceerde records uit pasr_store_catalog.
