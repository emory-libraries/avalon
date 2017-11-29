/**
 * @class MEJSUtility
 * @classdesc Utility class of helper functions for the MEJS Avalon wrapper file.
 */
class MEJSUtility {
  /**
   * Create HTML markup for <audio> or <video> element
   * @function createHTML5MediaNode
   * @return {string} markup - HTML markup containing <audio> or <video> and <source>s
   */
  createHTML5MediaNode(mediaType, currentStreamInfo) {
    let markup = ''
    let node = null

    // Create <video> markup
    if (mediaType === 'video') {
      node = document.createElement('video')
      node.setAttribute('id', 'mejs-avalon-video')
      node.setAttribute('controls', '')
      node.setAttribute('width', '450')
      node.setAttribute('height', '309')
      node.setAttribute('style', 'width: 100%; height: 100%')
      if (currentStreamInfo.poster_image) {
        node.setAttribute('poster', currentStreamInfo.poster_image)
      }
      node.setAttribute('preload', 'true')
      node.classList.add('mejs-avalon')
      node.classList.add('invisible')

      // Add <source>s
      currentStreamInfo.stream_hls.map((source) => {
        markup += `<source src="${source.url}" type="application/x-mpegURL" data-quality="${source.quality}"/>`
      })

      // Add captions
      if (currentStreamInfo.captions_path) {
        markup += `<track srclang="en" kind="subtitles" type="${currentStreamInfo.captions_format}" src="${currentStreamInfo.captions_path}"></track>`
      }
    }
    // Create <audio> markup
    if (mediaType === 'audio') {
      node = document.createElement('audio')
      node.setAttribute('id', 'mejs-avalon-audio')
      node.setAttribute('controls', '')
      node.setAttribute('style', 'width: 100%;')
      node.setAttribute('preload', 'true')
      node.classList.add('mejs-avalon')
      node.classList.add('invisible')

      // Add <source>s
      currentStreamInfo.stream_hls.map((source) => {
        markup += `<source src="${source.url}" data-quality="${source.quality}" data-plugin-type="native" type="application/x-mpegURL" />`
      })
      markup += `</audio>`
    }
    node.innerHTML = markup
    return node
  }

  /**
   * Create a map object which represents clickable time range segments within the media object
   * @function createSegmentsMap
   * @return {Object} segmentsMap Mapping of all current segments, key'd on the
   * <a> element's 'id' attribute
   */
  createSegmentsMap (el, currentStreamInfo) {
    let segmentsMap = {}
    const segmentEls = (el) ? [].slice.call(el.querySelectorAll('[data-segment="' + currentStreamInfo.id + '"]')) : []

    segmentEls.forEach((el) => {
      if (el.id) {
        segmentsMap[el.id] = Object.assign({}, el.dataset)
      }
    })
    return segmentsMap
  }

  /**
   * Get the segment for player's current time value (if one exists)
   * @function getActiveSegmentId
   * @return {string} the active segment id
   */
  getActiveSegmentId (segmentsMap, currentTime) {
    let activeId = ''

    for (let segmentId in segmentsMap) {
      if (segmentsMap.hasOwnProperty(segmentId)) {
        let begin = parseFloat(segmentsMap[segmentId].fragmentbegin)
        let end = parseFloat(segmentsMap[segmentId].fragmentend)

        if ( (segmentsMap.hasOwnProperty(segmentId)) && (currentTime >= begin && currentTime < end) ) {
          activeId = segmentId
        }
      }
    }
    return activeId
  }

  /**
   * Update section links to reflect active section playing
   * @function highlightSectionLink
   * @param  {string} segmentId - HTML node of section link clicked on <a>
   * @return {void}
   */
  highlightSectionLink (segmentId) {
    const accordionEl = document.getElementById('accordion')
    const htmlCollection = accordionEl.getElementsByClassName('playable wrap')
    let segmentLinks = [].slice.call(htmlCollection)
    let segmentEl = document.getElementById(segmentId)

    // Clear "active" style on all section links
    segmentLinks.forEach((segmentLink) => {
      segmentLink.classList.remove('current-stream')
      segmentLink.classList.remove('current-section')
    })
    if (segmentEl) {
      // Add style to clicked segment link
      segmentEl.classList.add('current-stream')
      // Add style to section title
      document.getElementById('section-title-' + segmentEl.dataset.segment).classList.add('current-section')
    }
  }

}
