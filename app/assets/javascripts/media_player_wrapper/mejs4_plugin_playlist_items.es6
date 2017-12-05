'use strict';

/**
 * Playlist Items plugin
 *
 * A custom Avalon MediaElement 4 plugin for handling playlist item interactions
 */

// Feature configuration
Object.assign(mejs.MepDefaults, {
    // Any variable that can be configured by the end user belongs here.
    // Make sure is unique by checking API and Configuration file.
    // Add comments about the nature of each of these variables.
});


Object.assign(MediaElementPlayer.prototype, {

    /**
     * Feature constructor.
     *
     * Always has to be prefixed with `build` and the name that will be used in MepDefaults.features list
     * @param {MediaElementPlayer} player
     * @param {HTMLElement} controls
     * @param {HTMLElement} layers
     * @param {HTMLElement} media
     */
    buildplaylistItems (player, controls, layers, media) {
        // This allows us to access options and other useful elements already set.
        // Adding variables to the object is a good idea if you plan to reuse
        // those variables in further operations.
        const t = this;
        let playlistItemsObj = t.playlistItemsObj;

        playlistItemsObj.mejsUtility = new MEJSUtility();
        playlistItemsObj.player = player;
        playlistItemsObj.currentStreamInfo = mejs4AvalonPlayer.currentStreamInfo;
        // Click listeners for the DOM
        playlistItemsObj.addClickListeners();
        // Handle continuous MEJS time update event
        media.addEventListener('timeupdate', playlistItemsObj.handleTimeUpdate.bind(this));
        // Set current playing item
        playlistItemsObj.setCurrentPlayingItem();
    },

    // Optionally, each feature can be destroyed setting a `clean` method

    /**
     * Feature destructor.
     *
     * Always has to be prefixed with `clean` and the name that was used in MepDefaults.features list
     * @param {MediaElementPlayer} player
     * @param {HTMLElement} controls
     * @param {HTMLElement} layers
     * @param {HTMLElement} media
     */
    cleanplaylistItems (player, controls, layers, media) {
      // Remove click listener on playlist items
      $('#right-column').find('.side-playlist').off('click');
    },

    // Other optional public methods (all documented according to JSDoc specifications)

    /**
     * The 'playlistItemsObj' object acts as a namespacer for this plugin's
     * specific variables and methods, so as not to pollute global or MEJS scope.
     * @type {Object}
     */
    playlistItemsObj: {
      /**
       * Add click listener for the playlist items sidebar
       * @function addClickListeners
       * @return {void}
       */
      addClickListeners() {
        if (this.$sidePlaylist) {
          // Handle click on entire Playlists right column area
          this.$sidePlaylist.on('click', (e) => {
            // Only handle clicks on <a> elements
            if (e.target.nodeName === 'A') {
              this.handleClick(e.target)
            }
          });
        }
      },

      /**
       * Get new master file and tear down and build up a new MEJS player
       * @param  {HTMLElement} el <a> anchor element of new playlist item being processed
       * @return {void}
       */
      ajaxGetNewMedia(el) {
        const dataSet = el.dataset;

        $.ajax({
          url: `http://localhost:3000/media_objects/${dataSet.mediaObjectId}/section/${dataSet.masterFileId}/stream.js`,
          dataType: 'json'
        }).done((response) => {
          console.log('response', response);
          mejs4AvalonPlayer.removePlayer();
          mejs4AvalonPlayer.currentStreamInfo = response;
          mejs4AvalonPlayer.mediaType = this.mejsUtility.getMediaType(response.is_video);
          mejs4AvalonPlayer.createNewPlayer();
        }).fail((error) => {
          console.log('error', error);
        })
      },

      /**
       * Determine whether we need to grab a new master file, or can use the existing file
       * @param  {HTMLElement} el <a> anchor element of the new playlist item being processed
       * @return {void}
       */
      analyzeNewItemSource(el) {
        this.updatePlaylistItemsList(el);
        // Same media file?
        if (this.currentStreamInfo.id === el.dataset.masterFileId) {
          this.setupNextItem();
        }
        // Need to grab a new media file
        else {
          this.ajaxGetNewMedia(el)
        }
      },

      currentStreamInfo: null,

      getNextItem() {
        return this.$nowPlayingLi.next('li');
      },

      /**
       * Handle click event on a playlist item
       * @param  {MouseEvent} e Mouse click event
       * @return {void}   [description]
       */
      handleClick(el) {
        this.analyzeNewItemSource(el);
      },

      /**
       * Handle MEJS's continuous time event
       * @return {void}
       */
      handleTimeUpdate() {
        // Playlist item's end time is reached
        if (this.playlistItemsObj.itemEnded()) {
          this.playlistItemsObj.player.pause();

          let $nextItem = this.playlistItemsObj.getNextItem();
          if ($nextItem) {
            let el = $nextItem.find('a')[0];
            this.playlistItemsObj.analyzeNewItemSource(el);
          }
        }
      },

      isAutoplay() {
        return !$('input[name="autoadvance"]').parent('.toggle').hasClass('off');
      },

      itemEnded() {
        console.log('this.player.getCurrentTime()', this.player.getCurrentTime());
        return this.player.getCurrentTime() > this.startEndTimes.end;
      },

      $nowPlayingLi: null,

      /**
       * Set the now playing item helper variable, and update start end times for
       * current playing item
       * @function setCurrentPlayingItem
       * @return {void}
       */
      setCurrentPlayingItem() {
        const t = this;
        // Set current playing item
        t.$nowPlayingLi = t.$sidePlaylist.find('li.now_playing');
        t.updateStartEndTimes(t.$nowPlayingLi.find('a').data());
      },

      /**
       * Wrapper function for playing next item in the list
       * @function setupNextItem
       * @return {void}
       */
      setupNextItem() {
        this.setCurrentPlayingItem();
        this.player.setCurrentTime(this.startEndTimes.start);
        mejs4AvalonPlayer.highlightTimeRail([
          this.startEndTimes.start,
          this.startEndTimes.end
        ]);
        if (this.isAutoplay()) {
          this.player.play();
        }
      },

      /**
       * Helper jQuery object for side playlist element which is used a few times in this class
       * @type {Object}
       */
      $sidePlaylist: $('#right-column').find('.side-playlist') || null,

      /**
       * Helper object initializer to store current playlist item's start and stop times
       * @type {Object}
       */
      startEndTimes: {
        start: null,
        end: null
      },

      /**
       * Update playlist item start and end times
       * @function updateStartEndTimes
       * @param  {Object} dataSet HTML element "dataset" property
       * @return {void}
       */
      updateStartEndTimes(dataSet) {
        this.startEndTimes.start = parseInt(dataSet.clipStartTime, 10)/1000;
        this.startEndTimes.end = parseInt(dataSet.clipEndTime, 10)/1000;
      },

      /**
       * Update styles on the playlist items list
       * @function updatePlaylistItemsList
       * @param  {HTMLElement} el The <a> item HTML element which is the new item
       * @return {void}
       */
      updatePlaylistItemsList(el) {
        const liItems = this.$sidePlaylist[0].getElementsByTagName('li');
        let array = [ ...liItems];
        let clickedEl = el.parentNode;
        const arrowNode = document.createElement('i');

        arrowNode.className = `fa fa-arrow-circle-right`;

        // Loop through all children list items
        array.forEach(li => {
          const children = [...li.children];
          let arrow = children.find(e => e.nodeName === 'I');
          // Remove styles
          li.classList.remove('now_playing');
          li.classList.remove('queue');
          if (arrow) {
            li.removeChild(arrow);
          }
          // Conditionally add styles to the item clicked
          if (li === clickedEl) {
            li.insertBefore(arrowNode, el);
            li.classList.add('now_playing');
          } else {
            li.classList.add('queue');
          }
        })
      }
    }

});
