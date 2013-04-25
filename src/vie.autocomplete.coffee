# VIE autocomplete uses the VIE.find service method to make autocomplete suggestions.
# The VIE.find method can query different backend or frontend data sources.
# This demo goes to the default Apache Stanbol backend.
#
#     var vie = new VIE();
#     vie.use(new vie.StanbolService({
#         url : "http://dev.iks-project.eu:8081",
#         proxyDisabled: true
#     }));
#
#     $('.search')
#     .vieAutocomplete({
#         vie: vie,
#         select: function(e, ui){
#             console.log(ui);
#         }
#     });

# default VIE instance with stanbol service
vie = new VIE()
vie.use(new vie.StanbolService({
    url : "http://dev.iks-project.eu:8080",
    proxyDisabled: true
}));

jQuery.widget "IKS.vieAutocomplete",
    # The widget **options** are:
    options:
        # * VIE instance.
        vie: vie
        # * callback for selection event
        select: (e, ui) ->
        urifield: null
        # * The field to search in.
        field: "rdfs:label"
        # * VIE service to use (right now only one)
        services: "stanbol"
        debug: false
        # * Define Entity properties for finding depiction
        showTooltip: true
        depictionProperties: [
          "foaf:depiction"
          "schema:thumbnail"
        ]
        # * Define Entity properties for finding the label
        labelProperties: [
          "rdfs:label"
          "skos:prefLabel"
          "schema:name"
          "foaf:name"
        ]
        # * Define Entity properties for finding the description
        descriptionProperties: [
          "rdfs:comment"
          "skos:note"
          "schema:description"
          "skos:definition"
            property: "skos:broader"
            makeLabel: (propertyValueArr) ->
              labels = _(propertyValueArr).map (termUri) ->
                # extract the last part of the uri
                termUri
                .replace(/<.*[\/#](.*)>/, "$1")
                .replace /_/g, "&nbsp;"
              "Subcategory of #{labels.join ', '}."
          ,
            property: "dcterms:subject"
            makeLabel: (propertyValueArr) ->
              labels = _(propertyValueArr).map (termUri) ->
                # extract the last part of the uri
                termUri
                .replace(/<.*[\/#](.*)>/, "$1")
                .replace /_/g, "&nbsp;"
              "Subject(s): #{labels.join ', '}."
        ]
        stanbolIncludeLocalSite: false
        # * If label and description is not available in the user's language 
        # look for a fallback.
        fallbackLanguage: "en"
        styleClass: "vie-autocomplete"
        # * type label definition
        getTypes: ->
          [
            uri:   "#{@ns.dbpedia}Place"
            label: 'Place'
          ,
            uri:   "#{@ns.dbpedia}Person"
            label: 'Person'
          ,
            uri:   "#{@ns.dbpedia}Organisation"
            label: 'Organisation'
          ,
            uri:   "#{@ns.skos}Concept"
            label: 'Concept'
          ]
        # * entity source label definition
        getSources: ->
          [
            uri: "http://dbpedia.org/resource/"
            label: "dbpedia"
          ,
            uri: "http://sws.geonames.org/"
            label: "geonames"
          ]
        source: (req, resp) ->
          @_logger.info "req:", req
          properties = _.flatten [
            @options.labelProperties
            @options.descriptionProperties
            @options.depictionProperties
          ]
          properties = _(properties).map (prop) ->
            if typeof prop is "object"
              prop.property
            else
              prop
          # call VIE.find
          # if @options.stanbolIncludeLocalSite TODO implement multiple find requests and result merging
          waitingfor = 0
          # Final list of results
          mergedEntityList = []
          # intermediate list of resultlists, indexed by priority
          listOfResultLists = []
          getSuccessCallback = (term, priority) =>
            (entityList) =>
              _.defer =>
                waitingfor--
                @_logger.info term, priority, "resp:", entityList
                # @_logger.info priority, "resp:", _(entityList).map (ent) -> ent.id
                limit = 10
                # remove descriptive entity
                # TODO move to VIE
                entityList = _(entityList).filter (ent) ->
                  return false if ent.getSubject().replace(/^<|>$/g, "") is "http://www.iks-project.eu/ontology/rick/query/QueryResultSet"
                  return true
                listOfResultLists[priority] = listOfResultLists[priority] or []
                listOfResultLists[priority] = listOfResultLists[priority].concat entityList
                # mergedEntityList = mergedEntityList.concat entityList
                if waitingfor is 0
                  # Sort by score
                  console.info "listOfResultLists", listOfResultLists
                  _.chain(listOfResultLists)
                  .compact()
                  .each (resultList) ->
                    sortedList = _(resultList).sortBy (e) ->
                      s = e.get '<http://stanbol.apache.org/ontology/entityhub/query#score>'
                      if typeof s is "object"
                        s = _.max(s)
                      return 0 - s
                    mergedEntityList = mergedEntityList.concat sortedList
                  ###
                  @_logger.info _(mergedEntityList).map (e) ->
                    uri = e.getSubject()
                    s = e.get '<http://stanbol.apache.org/ontology/entityhub/query#score>'
                    return "#{uri}: #{s}"
                  ###
                  @_logger.info mergedEntityList
                  res = _(mergedEntityList.slice(0, limit)).map (entity) =>
                    return {
                    key: entity.getSubject().replace /^<|>$/g, ""
                    label: "#{@_getLabel entity} @ #{@_sourceLabel entity.id}"
                    value: @_getLabel entity
                    getUri: ->
                      @key
                    }
                  resp res

          waitingfor++
          term = "#{req.term}#{if req.term.length > 3 then '*'  else ''}"
          @options.vie
          .find({
            term: term
            field: @options.field
            properties: properties
          })
          .using(@options.services).execute()
          # error handling
          .fail (e) =>
            @_logger.error "Something wrong happened at stanbol find:", e
          .success getSuccessCallback term, 3

          if req.term.length > 3
            waitingfor++
            @options.vie
              .find({
                term: req.term
                field: @options.field
                properties: properties
              })
              .using(@options.services).execute()
              # error handling
              .fail (e) =>
                @_logger.error "Something wrong happened at stanbol find:", e
              .success getSuccessCallback req.term, 2

          if @options.stanbolIncludeLocalSite
            @_logger.log "stanbolIncludeLocalSite"
            waitingfor++
            term = "#{req.term}#{if req.term.length > 3 then '*'  else ''}"
            @options.vie
            .find({
              term: term
              field: @options.field
              properties: properties
              local: true
            })
            .using(@options.services).execute()
            # error handling
            .fail (e) =>
              @_logger.error "Something wrong happened at stanbol find:", e
            .success getSuccessCallback 'local:' + term, 1
    _create: ->
      @_logger = if @options.debug then console else
        info: ->
        warn: ->
        error: ->
        log: ->
      @menuContainer = jQuery "<span class='#{@options.styleClass}'/>"
      @menuContainer.appendTo 'body'
      @_instantiateAutocomplete()

    _destroy: ->
      @menuContainer.remove()
    _instantiateAutocomplete: ->
      widget = @
      @element
      .autocomplete
        # define where do suggestions come from
        source: (req, resp) =>
          @options.source.apply @, [req, resp]
        # create tooltip on menu elements when menu opens
        open: (e, ui) ->
          widget._logger.info "autocomplete.open", e, ui
          if widget.options.showTooltip
            uiMenu = $(this).data().autocomplete?.menu or $(this).data().uiAutocomplete.menu
            $('.ui-menu-item', uiMenu.activeMenu)
            .each ->
              item = $( @ ).data()["item.autocomplete"] or $( @ ).data()["uiAutocompleteItem"] or $( @ ).data()["ui-autocomplete-item"]
              uri = item.getUri()
              $(@).entitypreview
                vie: widget.options.vie
                uri: uri
            $('.ui-menu-item', uiMenu.activeMenu).first().parent().unbind('menufocus').bind 'menufocus', (e, ui) =>
              console.info 'fire focusin'
              ui.item.trigger('focusin', ui)
            $('.ui-menu-item', uiMenu.activeMenu).first().parent().unbind('menublur').bind 'menublur', (e, ui) =>
              $(':IKS-Entitypreview').trigger('blur')

        focus: (e, ui) ->
          console.info "focus", ui
        # An entity selected, annotate
        blur: (e, ui) ->
          console.info 'autocomplete.blur event', e, ui
        select: (e, ui) =>
          uiMenu = $(e.target).data().autocomplete?.menu or $(e.target).data().uiAutocomplete.menu
          $('.ui-menu-item', uiMenu.activeMenu).each ->
            $(@)
            #.entitypreview('hide')
            .entitypreview('destroy')
          _.defer =>
            @options.select e, ui
            @_logger.info "autocomplete.select", e.target, ui
            if widget.options.urifield
              widget.options.urifield.val ui.item.key
          true
        appendTo: @menuContainer
    _getUserLang: ->
      window.navigator.language.split("-")[0]

    _getLabel: (entity) ->
      preferredFields = @options.labelProperties
      preferredLanguages = [@_getUserLang(), @options.fallbackLanguage]
      VIE.Util.getPreferredLangForPreferredProperty entity, preferredFields, preferredLanguages

    # make a label for the entity source based on options.getSources()
    _sourceLabel: (src) ->
      @_logger.warn "No source" unless src
      return "" unless src
      sources = @options.getSources()
      sourceObj = _(sources).detect (s) -> src.indexOf(s.uri) isnt -1
      if sourceObj
        sourceObj.label
      else
        src.split("/")[2]

