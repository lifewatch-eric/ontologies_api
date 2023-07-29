require 'sinatra/base'

module Sinatra
  module Helpers
    module SubmissionHelper

      def submission_attributes_all
        out = [LinkedData::Models::OntologySubmission.embed_values_hash]
        out << {:contact=>[:name, :email]}
        out << {:ontology=>[:acronym, :name, :administeredBy, :group, :viewingRestriction, :doNotUpdate, :flat,
                            :hasDomain, :summaryOnly, :acl, :viewOf, :ontologyType]}

        out
      end

      def retrieve_submissions(options)
        status = (options[:status] || "RDF").to_s.upcase
        status = "RDF" if status.eql?("READY")
        any = status.eql?("ANY")
        include_views = options[:also_include_views] || false
        includes, page, size, order_by, _ = settings_params(LinkedData::Models::OntologySubmission)
        includes << :submissionStatus unless includes.include?(:submissionStatus)

        submissions_query = LinkedData::Models::OntologySubmission
        if any
          submissions_query = submissions_query.where
        else
          submissions_query = submissions_query.where({ submissionStatus: [code: status] })
        end

        submissions_query = apply_submission_filters(submissions_query)
        submissions_query = submissions_query.filter(Goo::Filter.new(ontology: [:viewOf]).unbound) unless include_views
        submissions_query = submissions_query.filter(filter) if filter?

        # When asking to display all metadata, we are using bring_remaining on each submission. Slower but best way to retrieve all attrs
        if includes_param.first == :all
          includes = [:submissionId, { :contact => [:name, :email],
                                       :ontology => [:administeredBy, :acronym, :name, :summaryOnly, :ontologyType, :viewingRestriction, :acl,
                                                     :group, :hasDomain, :views, :viewOf, :flat, :notes, :reviews, :projects],
                                       :submissionStatus => [:code], :hasOntologyLanguage => [:acronym], :metrics => [:classes, :individuals, :properties] },
                      :submissionStatus]
        else
          if includes.find { |v| v.is_a?(Hash) && v.keys.include?(:ontology) }
            includes << { :ontology => [:administeredBy, :acronym, :name, :viewingRestriction, :group, :hasDomain, :notes, :reviews, :projects, :acl, :viewOf] }
          end

          if includes.find { |v| v.is_a?(Hash) && v.keys.include?(:contact) }
            includes << { :contact => [:name, :email] }
          end
        end

        submissions = submissions_query.include(includes)
        if page?
          submissions.page(page, size).all
        else
          submissions.to_a
        end
      end

      def include_ready?(options)
        options[:status] && options[:status].to_s.upcase.eql?("READY")
      end

    end
  end
end

helpers Sinatra::Helpers::SubmissionHelper