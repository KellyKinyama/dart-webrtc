

final setIceAttr = <T extends keyof SdpIceAttributes>(section: Sdp | SdpMediaSection, field:T, value: SdpIceAttributes[T]) => {
  if (!section.ice) {
    section.ice = {
      ufrag: '',
      pwd: '',
      options: []
    }
  }
  section.ice[field] = value;
}