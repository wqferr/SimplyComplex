let embedDiv = document.getElementById("welchlabsYoutubeEmbed");
function doEmbedYoutube() {
    embedDiv.innerHTML = '<iframe width="560" height="315" src="https://www.youtube-nocookie.com/embed/pNp8Qf20-sA?si=WWMDR2TbXKvmNHyC&amp;start=206" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen></iframe>';
    document.removeEventListener("scroll", doEmbedYoutube)
}
document.addEventListener("scroll", doEmbedYoutube);
