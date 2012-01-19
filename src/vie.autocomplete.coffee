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
        # * VIE service to use (right now only one)
        services: "stanbol"
        debug: false
        # * Define Entity properties for finding depiction
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
        # * If label and description is not available in the user's language 
        # look for a fallback.
        fallbackLanguage: "en"
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
    _create: ->
        @_logger = if @options.debug then console else 
            info: ->
            warn: ->
            error: ->
            log: ->
        @_instantiateAutocomplete()

    _instantiateAutocomplete: ->
        widget = @
        @element
        .autocomplete
            # define where do suggestions come from
            source: (req, resp) ->
                widget._logger.info "req:", req
                # call VIE.find
                widget.options.vie.find({term: "#{req.term}#{if req.term.length > 3 then '*'  else ''}"})
                .using(widget.options.services).execute()
                # error handling
                .fail (e) ->
                    widget._logger.error "Something wrong happened at stanbol find:", e
                .success (entityList) ->
                  _.defer =>
                    widget._logger.info "resp:", _(entityList).map (ent) ->
                        ent.id
                    limit = 10
                    # remove descriptive entity
                    # TODO move to VIE
                    entityList = _(entityList).filter (ent) ->
                        return false if ent.getSubject().replace(/^<|>$/g, "") is "http://www.iks-project.eu/ontology/rick/query/QueryResultSet"
                        return true
                    res = _(entityList.slice(0, limit)).map (entity) ->
                        return {
                            key: entity.getSubject().replace /^<|>$/g, ""
                            label: "#{widget._getLabel entity} @ #{widget._sourceLabel entity.id}"
                            value: widget._getLabel entity
                        }
                    resp res
            # create tooltip on menu elements when menu opens
            open: (e, ui) ->
                widget._logger.info "autocomplete.open", e, ui
                if widget.options.showTooltip
                    $(this).data().autocomplete.menu.activeMenu
                    .tooltip
                        items: ".ui-menu-item"
                        hide: 
                            effect: "hide"
                            delay: 50
                        show:
                            effect: "show"
                            delay: 50
                        content: (response) ->
                            uri = $( @ ).data()["item.autocomplete"].getUri()
                            widget._createPreview uri, response
                            "loading..."
            # An entity selected, annotate
            select: (e, ui) =>
                @options.select e, ui
                @_logger.info "autocomplete.select", e.target, ui
                if widget.options.urifield
                    widget.options.urifield.val ui.item.key

    _getUserLang: ->
        window.navigator.language.split("-")[0]

    _getDepiction: (entity, picSize) ->
        preferredFields = @options.depictionProperties
        # field is the first property name with a value
        field = _(preferredFields).detect (field) ->
            true if entity.get field
        # fieldValue is an array of at least one value
        if field && fieldValue = _([entity.get field]).flatten()
            # 
            depictionUrl = _(fieldValue).detect (uri) ->
                true if uri.indexOf("thumb") isnt -1
            .replace /[0-9]{2..3}px/, "#{picSize}px"
            depictionUrl

    _getLabel: (entity) ->
        preferredFields = @options.labelProperties
        preferredLanguages = [@_getUserLang(), @options.fallbackLanguage]
        @_getPreferredLangForPreferredProperty entity, preferredFields, preferredLanguages

    _getDescription: (entity) ->
        preferredFields = @options.descriptionProperties
        preferredLanguages = [@_getUserLang(), @options.fallbackLanguage]
        @_getPreferredLangForPreferredProperty entity, preferredFields, preferredLanguages

    _getPreferredLangForPreferredProperty: (entity, preferredFields, preferredLanguages) ->
        # Try to find a label in the preferred language
        for lang in preferredLanguages
            for property in preferredFields
                # property can be a string e.g. "skos:prefLabel"
                if typeof property is "string" and entity.get property
                    labelArr = _.flatten [entity.get property]
                    # select the label in the user's language
                    label = _(labelArr).detect (label) =>
                        true if label.indexOf("@#{lang}") > -1
                    if label
                        return label.replace /(^\"*|\"*@..$)/g, ""
                # property can be an object like {property: "skos:broader", makeLabel: function(propertyValueArr){return "..."}}
                else if typeof property is "object" and entity.get property.property
                    valueArr = _.flatten [entity.get property.property]
                    valueArr = _(valueArr).map (termUri) ->
                        if termUri.isEntity then termUri.getSubject() else termUri
                    return property.makeLabel valueArr
        ""
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

