package app.lrvdlinden.pasrzakelijk.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.PanTool
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.ShowChart
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.core.L
import app.lrvdlinden.pasrzakelijk.data.Account
import kotlinx.coroutines.launch

private enum class Mode { SignIn, SignUp, Forgot, CheckInbox }

/** Welkom en inloggen met je Pasr-account (zelfde account als op pasr.nl/zakelijk en in de app Pasr). */
@Composable
fun WelcomeScreen() {
    var mode by rememberSaveable { mutableStateOf(Mode.SignIn) }
    var firstName by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var shownAt by rememberSaveable { mutableLongStateOf(System.currentTimeMillis()) }
    var busy by rememberSaveable { mutableStateOf(false) }
    var message by rememberSaveable { mutableStateOf<String?>(null) }
    var info by rememberSaveable { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val haptics = rememberHaptics()
    val open = rememberOpenUrl()

    fun switch(to: Mode) { mode = to; message = null; info = null; shownAt = System.currentTimeMillis() }

    val mailOK = email.contains("@") && email.contains(".")
    val valid = when (mode) {
        Mode.SignIn -> mailOK && password.isNotEmpty()
        Mode.SignUp -> mailOK && password.length >= 8 && firstName.isNotBlank()
        Mode.Forgot -> mailOK
        Mode.CheckInbox -> true
    }

    fun submit() {
        if (!valid || busy) return
        busy = true; message = null; info = null
        scope.launch {
            try {
                when (mode) {
                    Mode.SignIn -> { Account.signIn(email, password); haptics.success() }
                    Mode.SignUp -> {
                        val r = Account.signUp(firstName, email, password, "", System.currentTimeMillis() - shownAt)
                        if (r == Account.SignUpResult.CheckInbox) switch(Mode.CheckInbox) else haptics.success()
                    }
                    Mode.Forgot -> {
                        Account.sendPasswordReset(email)
                        info = L("Als er een account is met dit adres, krijg je een mail met een link om een nieuw wachtwoord te kiezen.")
                    }
                    Mode.CheckInbox -> switch(Mode.SignIn)
                }
            } catch (e: Exception) {
                message = e.message
                haptics.error()
            } finally {
                busy = false
            }
        }
    }

    Box(Modifier.fillMaxSize().background(Pz.bg), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = 520.dp)
                .fillMaxWidth()
                .safeDrawingPadding()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            ZakelijkLogo(26f, Modifier.padding(top = 24.dp))
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(L("Digitale stempelkaarten voor je zaak"), fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, color = Pz.text)
                Text(L("Scan de kaart van je klant en zet een stempel. Alleen jij en je medewerkers kunnen stempels zetten."), color = Pz.muted, fontSize = 17.sp)
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Feature(Icons.Outlined.QrCodeScanner, L("Scannen aan de kassa"), L("Stempel erbij, beloning inwisselen of ongedaan maken."))
                Feature(Icons.Outlined.Group, L("Medewerkers"), L("Nodig je team uit; zij zien alleen de scanner."))
                Feature(Icons.Outlined.ShowChart, L("Overzicht en logboek"), L("Zie per dag wat er gebeurt en wie wat deed."))
            }
            if (mode == Mode.CheckInbox) {
                CardBox(padding = 18.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(Icons.Outlined.MarkEmailUnread, null, tint = Pz.mint, modifier = Modifier.size(36.dp))
                        Text(L("Check je mail"), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Pz.text)
                        Text(L("We hebben je een mail gestuurd. Tik op de knop in die mail om je e-mailadres te bevestigen en log daarna hier in."), color = Pz.muted)
                        info?.let { SuccessLine(it) }
                        message?.let { ErrorLine(it) }
                        BigButton(L("Naar inloggen"), { switch(Mode.SignIn) })
                        LinkButton(L("Mail opnieuw sturen"), {
                            scope.launch {
                                try { Account.resendConfirmation(email); info = L("Verstuurd. Kijk ook bij ongewenste mail.") } catch (e: Exception) { message = e.message }
                            }
                        })
                    }
                }
            } else {
                CardBox(padding = 18.dp) {
                    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        Text(
                            when (mode) { Mode.SignIn -> L("Inloggen"); Mode.SignUp -> L("Account maken"); else -> L("Wachtwoord vergeten") },
                            fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Pz.text,
                        )
                        if (mode == Mode.SignIn) {
                            Text(L("Log in met je Pasr-account. Ben je medewerker? Gebruik het account waarmee je de uitnodiging accepteert."), color = Pz.muted, fontSize = 15.sp)
                        }
                        if (mode == Mode.SignUp) {
                            PzField(firstName, { firstName = it }, L("Voornaam"), capitalization = KeyboardCapitalization.Words)
                        }
                        PzField(
                            email, { email = it.trim() }, L("E-mailadres"), keyboardType = KeyboardType.Email,
                            capitalization = KeyboardCapitalization.None, autoCorrect = false,
                            imeAction = if (mode == Mode.Forgot) ImeAction.Send else ImeAction.Next,
                            onIme = { if (mode == Mode.Forgot) submit() },
                        )
                        if (mode != Mode.Forgot) {
                            PzField(
                                password, { password = it }, L("Wachtwoord"), keyboardType = KeyboardType.Password, password = true,
                                capitalization = KeyboardCapitalization.None, autoCorrect = false, imeAction = ImeAction.Go, onIme = { submit() },
                            )
                        }
                        message?.let { ErrorLine(it) }
                        info?.let { SuccessLine(it) }
                        BigButton(
                            when (mode) { Mode.SignUp -> L("Account maken"); Mode.Forgot -> L("Stuur een link"); else -> L("Inloggen") },
                            { submit() }, enabled = valid, busy = busy,
                        )
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            if (mode == Mode.SignIn) {
                                LinkButton(L("Account maken"), { switch(Mode.SignUp) })
                                LinkButton(L("Wachtwoord vergeten?"), { switch(Mode.Forgot) })
                            } else {
                                LinkButton(L("Ik heb al een account"), { switch(Mode.SignIn) })
                            }
                        }
                    }
                }
                Text(L("Met een account ga je akkoord met de privacyverklaring van Pasr."), color = Pz.muted, fontSize = 13.sp)
                Row(
                    Modifier.clip(RoundedCornerShape(8.dp)).alpha(1f),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Outlined.PanTool, null, tint = Pz.accent, modifier = Modifier.size(14.dp))
                    LinkButton(L("Privacyverklaring"), { open("https://pasr.nl/privacy/#stempelkaarten-van-ondernemers") })
                }
                Spacer(Modifier.height(12.dp))
            }
        }
    }
}

@Composable
private fun Feature(icon: ImageVector, title: String, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(Pz.mint.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Pz.mint, modifier = Modifier.size(20.dp))
        }
        Column {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = Pz.text)
            Text(text, color = Pz.muted, fontSize = 15.sp)
        }
    }
}
