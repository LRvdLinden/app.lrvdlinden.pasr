package app.lrvdlinden.pasrzakelijk.ui.cards

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.lrvdlinden.pasrzakelijk.data.Account
import app.lrvdlinden.pasrzakelijk.data.Business
import app.lrvdlinden.pasrzakelijk.ui.Pz
import app.lrvdlinden.pasrzakelijk.ui.ScreenScaffold
import org.json.JSONArray
import org.json.JSONObject

private data class PromotionChoice(val id: String, val kind: String, val title: String, val product: JSONObject)

/** Eigen acties kiezen; export: afbeeldingen naar de Galerij en ZIP naar Downloads/Pasr. */
@Composable
fun PromoMaterialsScreen(business: Business) {
    var selected by remember { mutableStateOf<PromotionChoice?>(null) }
    var products by remember { mutableStateOf<List<PromotionChoice>>(emptyList()) }
    var busy by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var notice by remember { mutableStateOf("") }

    LaunchedEffect(business.id) {
        val choices = business.cards.map { card ->
            PromotionChoice("card:"+card.id, "Stempelkaart", card.name,
                JSONObject().put("kind","card").put("id",card.id).put("name",card.name)
                    .put("business",business.name).put("logo",card.logo ?: "")
                    .put("color",card.color).put("stamps_total",card.stampsTotal)
                    .put("reward",card.reward).put("published",card.published)
                    .put("join_url",card.joinURL))
        }.toMutableList()
        try {
            val rows=Account.rpc("pasr_business_coupon_list",JSONObject().put("p_business",business.id)) as? JSONArray
            for(i in 0 until (rows?.length() ?: 0)){
                val row=rows?.optJSONObject(i) ?: continue
                row.put("kind","coupon").put("business",business.name).put("color","#6A5CFF")
                choices.add(PromotionChoice("coupon:"+row.optString("id"),"Kortingscoupon",row.optString("title"),row))
            }
        }catch(e:Exception){error="Kortingscoupons laden mislukt: "+e.message}
        try {
            val rows=Account.rpc("pasr_business_promo_list",JSONObject().put("p_business",business.id)) as? JSONArray
            for(i in 0 until (rows?.length() ?: 0)){
                val row=rows?.optJSONObject(i) ?: continue
                row.put("kind","code").put("business",business.name).put("color","#6A5CFF")
                choices.add(PromotionChoice("code:"+row.optString("id"),"Actiecode",row.optString("title"),row))
            }
        }catch(e:Exception){error="Actiecodes laden mislukt: "+e.message}
        products=choices;busy=false
    }

    ScreenScaffold("Promotiemateriaal") {
        if(selected==null){
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(18.dp),
                verticalArrangement=Arrangement.spacedBy(12.dp)){
                Text("Kies een stempelkaart, kortingscoupon of actiecode. Maak social posts, Stories, banners of flyers in Licht en Donker.",color=Pz.text)
                if(busy)CircularProgressIndicator(color=Pz.accent)
                error?.let { Text(it,color=Pz.coral) }
                products.forEach { product ->
                    TextButton(onClick={selected=product}){
                        Text(product.kind+" · "+product.title,color=Pz.accent)
                    }
                }
                if(!busy&&products.isEmpty())Text("Maak eerst een actie in Acties.",color=Pz.muted)
                Text("PNG wordt opgeslagen in Galerij/Pasr. ZIP in Downloads/Pasr.",color=Pz.muted)
            }
        }else{
            val product=selected!!
            Column(Modifier.fillMaxSize()){
                TextButton(onClick={selected=null}){Text("‹ Kies een andere actie",color=Pz.accent)}
                Text(product.kind+" · "+product.title,modifier=Modifier.padding(horizontal=16.dp),color=Pz.text)
                if(notice.isNotEmpty())Text(notice,modifier=Modifier.padding(12.dp),color=Pz.muted)
                AndroidView(
                    modifier=Modifier.fillMaxWidth().weight(1f),
                    factory={ctx ->
                        WebView(ctx).apply {
                            settings.javaScriptEnabled=true
                            settings.domStorageEnabled=false
                            settings.allowFileAccess=false
                            settings.allowContentAccess=false
                            addJavascriptInterface(PromoExportAndroid(ctx){msg -> post{notice=msg} },"PasrAndroidExport")
                            webViewClient=object:WebViewClient(){
                                override fun shouldOverrideUrlLoading(view:WebView?,request:WebResourceRequest?):Boolean{
                                    return request?.url?.host!="pasr.nl"
                                }
                                override fun onPageFinished(view:WebView?,url:String?){
                                    val payload=JSONObject.quote(product.product.toString())
                                    view?.evaluateJavascript(
                                        "if(window.PasrPromo){window.PasrPromo.mount(document.getElementById('zk-flyer'),JSON.parse("+payload+"));}",null)
                                }
                            }
                            val html="""<!doctype html><html lang="nl"><head><meta name="viewport" content="width=device-width, initial-scale=1">
                              <link rel="stylesheet" href="https://pasr.nl/assets/style.css">
                              <link rel="stylesheet" href="https://pasr.nl/assets/zakelijk.css">
                              <script src="https://pasr.nl/assets/vendor/qrcode.js"></script>
                              <script src="https://pasr.nl/assets/promo.js"></script></head>
                              <body style="padding:14px"><main id="zk-flyer"></main></body></html>"""
                            loadDataWithBaseURL("https://pasr.nl/zakelijk/flyer/",html,"text/html","utf-8",null)
                        }
                    }
                )
            }
        }
    }
}

private class PromoExportAndroid(private val context:Context,private val feedback:(String)->Unit){
    @JavascriptInterface
    fun save(name:String,mime:String,b64:String){
        try {
            require(name.startsWith("Pasr-") && name.length<140 && !name.contains("/") && !name.contains("\\"))
            require(mime=="image/png"||mime=="application/zip")
            require(b64.length<95_000_000)
            val bytes=Base64.decode(b64,Base64.DEFAULT)
            require(bytes.size<75_000_000)
            val isImage=mime=="image/png"
            val resolver=context.contentResolver
            val values=ContentValues().apply{
                put(MediaStore.MediaColumns.DISPLAY_NAME,name)
                put(MediaStore.MediaColumns.MIME_TYPE,mime)
                if(Build.VERSION.SDK_INT>=29){
                    put(MediaStore.MediaColumns.RELATIVE_PATH,
                        (if(isImage)Environment.DIRECTORY_PICTURES else Environment.DIRECTORY_DOWNLOADS)+"/Pasr")
                    put(MediaStore.MediaColumns.IS_PENDING,1)
                }
            }
            val collection=if(isImage)MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                else if(Build.VERSION.SDK_INT>=29)MediaStore.Downloads.EXTERNAL_CONTENT_URI
                else MediaStore.Files.getContentUri("external")
            val uri=resolver.insert(collection,values)?:error("Bestand niet beschikbaar")
            try{
                resolver.openOutputStream(uri)?.use{it.write(bytes)}?:error("Opslaan mislukt")
                if(Build.VERSION.SDK_INT>=29){
                    values.clear();values.put(MediaStore.MediaColumns.IS_PENDING,0)
                    resolver.update(uri,values,null,null)
                }
                feedback(if(isImage)"Afbeelding opgeslagen in Galerij / Pasr"
                    else "ZIP opgeslagen in Downloads / Pasr")
            }catch(e:Exception){resolver.delete(uri,null,null);throw e}
        }catch(e:Exception){feedback("Opslaan mislukt: "+(e.message?:"onbekend"))}
    }
}
